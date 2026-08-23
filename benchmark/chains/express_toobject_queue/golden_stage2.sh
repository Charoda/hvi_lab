#!/bin/bash
# Stage 2: Add job payload schema validation (PERF-961)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding job payload schema validation (PERF-961)..."

USER_CTRL="src/controllers/user.controller.js"

python3 -c "
import sys

with open('$USER_CTRL', 'r') as f:
    content = f.read()

original = content

old_requires = '''const { userService } = require('../services');'''
new_requires = '''const { userService } = require('../services');
const crypto = require('crypto');

// PERF-961: Serialization with checksums
const serializationCache = new Map();

function serializeUser(user) {
  const serialized = user.toJSON ? user.toJSON() : user;
  const checksum = crypto.createHash('md5').update(JSON.stringify(serialized)).digest('hex').slice(0, 12);
  return { serialized, checksum };
}'''

content = content.replace(old_requires, new_requires)

# Patch getUser to use serialization
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
  // PERF-961: Serialize with checksum
  const { serialized, checksum } = serializeUser(user);
  serializationCache.set(req.params.userId, { checksum, ts: Date.now() });
  res.setHeader('X-Serialized', checksum);
  res.send(serialized);
});'''

content = content.replace(old_getUser, new_getUser)

if content == original:
    print('ERROR: Could not patch controller for serialization', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added serialization with checksums')
"

echo "Stage 2 complete."
