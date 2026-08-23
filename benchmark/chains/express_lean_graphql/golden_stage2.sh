#!/bin/bash
# Stage 2: Add response normalization (PERF-901)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding response normalization (PERF-901)..."

USER_CTRL="src/controllers/user.controller.js"

python3 -c "
import sys

with open('$USER_CTRL', 'r') as f:
    content = f.read()

original = content

old_requires = '''const { userService } = require('../services');'''
new_requires = '''const { userService } = require('../services');

// PERF-901: Response normalization
function normalizeResponse(obj) {
  if (typeof obj !== 'object' || obj === null) return obj;
  const plain = typeof obj.toJSON === 'function' ? obj.toJSON() : obj;
  return Object.keys(plain).sort().reduce((acc, key) => {
    acc[key] = plain[key];
    return acc;
  }, {});
}'''

content = content.replace(old_requires, new_requires)

# Patch getUser to normalize response
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
  // PERF-901: Normalize response field ordering
  const normalized = normalizeResponse(user);
  res.setHeader('X-Normalized', 'true');
  res.send(normalized);
});'''

content = content.replace(old_getUser, new_getUser)

if content == original:
    print('ERROR: Could not patch controller for normalization', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added response normalization')
"

echo "Stage 2 complete."
