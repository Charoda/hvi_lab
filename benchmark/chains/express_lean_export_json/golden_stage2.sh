#!/bin/bash
# Stage 2: Add response size tracking (PERF-881)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding response size tracking (PERF-881)..."

USER_CTRL="src/controllers/user.controller.js"

python3 -c "
import sys

with open('$USER_CTRL', 'r') as f:
    content = f.read()

original = content

old_requires = '''const { userService } = require('../services');'''

new_requires = '''const { userService } = require('../services');

// PERF-881: Response size tracking
function sendWithSize(res, body) {
  const json = typeof body === 'string' ? body : JSON.stringify(body);
  const byteLen = Buffer.byteLength(json, 'utf8');
  res.setHeader('Content-Length', byteLen);
  res.setHeader('X-Body-Size', byteLen);
  res.setHeader('Content-Type', 'application/json');
  return res.end(json);
}'''

content = content.replace(old_requires, new_requires)

# Patch getUser to use sendWithSize
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
  // PERF-881: Pre-calculate content length
  sendWithSize(res, user);
});'''

content = content.replace(old_getUser, new_getUser)

if content == original:
    print('ERROR: Could not patch controller for size tracking', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added response size tracking')
"

echo "Stage 2 complete."
