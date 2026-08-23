#!/bin/bash
# Stage 2: Add response deduplication (PERF-911)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding response deduplication (PERF-911)..."

USER_CTRL="src/controllers/user.controller.js"

python3 -c "
import sys

with open('$USER_CTRL', 'r') as f:
    content = f.read()

original = content

old_requires = '''const { userService } = require('../services');'''
new_requires = '''const { userService } = require('../services');
const crypto = require('crypto');

// PERF-911: Response deduplication with fingerprinting
const fingerprintCache = new Map();
const FINGERPRINT_TTL = 30000;

function getFingerprint(obj) {
  const str = JSON.stringify(obj);
  return crypto.createHash('md5').update(str).digest('hex');
}

function checkFingerprint(url, obj) {
  const fp = getFingerprint(obj);
  const cached = fingerprintCache.get(url);
  const isHit = cached && cached.fp === fp && (Date.now() - cached.ts < FINGERPRINT_TTL);
  fingerprintCache.set(url, { fp, ts: Date.now() });
  return isHit;
}'''

content = content.replace(old_requires, new_requires)

# Patch getUser to add fingerprint check
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
  // PERF-911: Check fingerprint for dedup
  const isDup = checkFingerprint(req.originalUrl, user);
  res.setHeader('X-Dedup-Hits', isDup ? '1' : '0');
  res.send(user);
});'''

content = content.replace(old_getUser, new_getUser)

if content == original:
    print('ERROR: Could not patch controller for dedup', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added response deduplication')
"

echo "Stage 2 complete."
