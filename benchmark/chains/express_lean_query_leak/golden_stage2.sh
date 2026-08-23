#!/bin/bash
# Stage 2: Add in-memory response caching for GET endpoints (PERF-851)
# Adds a simple Map-based cache with 60s TTL for GET /v1/users/:id.
# Caches the JSON response body string. Invalidates on mutations.
# Does NOT modify database queries — just caches res.send() output.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding in-memory response cache (PERF-851)..."

USER_CTRL="src/controllers/user.controller.js"

python3 -c "
import sys

with open('$USER_CTRL', 'r') as f:
    content = f.read()

original = content

# Add cache module after the timing helper
old_timing = '''// PERF-850: Response time tracking'''

new_timing = '''// PERF-851: In-memory response cache
const responseCache = new Map();
const CACHE_TTL_MS = 60 * 1000;

function getCacheKey(req) {
  return req.originalUrl || req.url;
}

function getCached(key) {
  const entry = responseCache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.ts > CACHE_TTL_MS) {
    responseCache.delete(key);
    return null;
  }
  return entry.body;
}

function setCache(key, body) {
  responseCache.set(key, { body, ts: Date.now() });
}

function invalidateCache(key) {
  responseCache.delete(key);
}

// PERF-850: Response time tracking'''

content = content.replace(old_timing, new_timing)

# Patch getUser to use cache
old_getUser = '''const getUser = catchAsync(async (req, res) => {
  const user = await userService.getUserById(req.params.userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  res.send(user);
});'''

new_getUser = '''const getUser = catchAsync(async (req, res) => {
  // PERF-851: Check response cache first
  const cacheKey = getCacheKey(req);
  const cached = getCached(cacheKey);
  if (cached) {
    res.setHeader('X-Cache', 'HIT');
    return res.json(JSON.parse(cached));
  }

  const user = await userService.getUserById(req.params.userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }

  // PERF-851: Cache the serialized response
  const body = JSON.stringify(user);
  setCache(cacheKey, body);
  res.setHeader('X-Cache', 'MISS');
  res.send(user);
});'''

content = content.replace(old_getUser, new_getUser)

# Patch updateUser to invalidate cache
old_updateUser = '''const updateUser = catchAsync(async (req, res) => {
  const user = await userService.updateUserById(req.params.userId, req.body);
  res.send(user);
});'''

new_updateUser = '''const updateUser = catchAsync(async (req, res) => {
  const user = await userService.updateUserById(req.params.userId, req.body);
  // PERF-851: Invalidate cache on mutation
  invalidateCache('/v1/users/' + req.params.userId);
  res.send(user);
});'''

content = content.replace(old_updateUser, new_updateUser)

# Patch deleteUser to invalidate cache
old_deleteUser = '''const deleteUser = catchAsync(async (req, res) => {
  await userService.deleteUserById(req.params.userId);
  res.status(httpStatus.NO_CONTENT).send();
});'''

new_deleteUser = '''const deleteUser = catchAsync(async (req, res) => {
  await userService.deleteUserById(req.params.userId);
  // PERF-851: Invalidate cache on deletion
  invalidateCache('/v1/users/' + req.params.userId);
  res.status(httpStatus.NO_CONTENT).send();
});'''

content = content.replace(old_deleteUser, new_deleteUser)

if content == original:
    print('ERROR: Could not patch user controller for caching', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added in-memory cache with 60s TTL to GET /v1/users/:id')
"

echo "Stage 2 complete."
