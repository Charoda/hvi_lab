#!/bin/bash
# Stage 2: Add ETag-based conditional response caching (PERF-861)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding ETag-based caching (PERF-861)..."

USER_CTRL="src/controllers/user.controller.js"

python3 -c "
import sys

with open('$USER_CTRL', 'r') as f:
    content = f.read()

original = content

# Add ETag helper after requires
old_requires = '''const { userService } = require('../services');'''

new_requires = '''const { userService } = require('../services');
const crypto = require('crypto');

// PERF-861: ETag-based conditional response caching
const etagCache = new Map();

function computeETag(body) {
  const str = typeof body === 'string' ? body : JSON.stringify(body);
  return crypto.createHash('md5').update(str).digest('hex').slice(0, 16);
}

function withETag(req, res, body) {
  const etag = computeETag(body);
  res.setHeader('ETag', etag);
  if (req.headers['if-none-match'] === etag) {
    return res.status(304).end();
  }
  etagCache.set(req.originalUrl, { etag, body: JSON.stringify(body), ts: Date.now() });
  return res.send(body);
}'''

content = content.replace(old_requires, new_requires)

# Patch getUser to use ETag
old_getUser = '''const getUser = catchAsync(async (req, res) => {
  const user = await userService.getUserById(req.params.userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  res.send(user);
});'''

new_getUser = '''const getUser = catchAsync(async (req, res) => {
  const user = await userService.getUserById(req.params.userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  // PERF-861: ETag conditional response
  withETag(req, res, user);
});'''

content = content.replace(old_getUser, new_getUser)

if content == original:
    print('ERROR: Could not patch user controller for ETag caching', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added ETag-based conditional caching to GET endpoints')
"

echo "Stage 2 complete."
