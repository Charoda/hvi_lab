#!/bin/bash
# Stage 2: Add response body hashing (PERF-871)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding response body hashing (PERF-871)..."

USER_CTRL="src/controllers/user.controller.js"

python3 -c "
import sys

with open('$USER_CTRL', 'r') as f:
    content = f.read()

original = content

old_requires = '''const { userService } = require('../services');'''

new_requires = '''const { userService } = require('../services');
const crypto = require('crypto');

// PERF-871: Response body hashing for dedup
const hashCache = new Map();
function computeBodyHash(body) {
  const str = typeof body === 'string' ? body : JSON.stringify(body);
  return crypto.createHash('sha256').update(str).digest('hex').slice(0, 16);
}

const wrapWithHash = (handler) => async (req, res, ...args) => {
  const origSend = res.send.bind(res);
  res.send = (body) => {
    const hash = computeBodyHash(body);
    res.setHeader('X-Content-Hash', hash);
    hashCache.set(req.originalUrl, { hash, ts: Date.now() });
    return origSend(body);
  };
  return handler(req, res, ...args);
};'''

content = content.replace(old_requires, new_requires)

# Wrap GET handlers in module.exports
content = content.replace(
    'getUsers,',
    'getUsers: wrapWithHash(getUsers),'
).replace(
    'getUser,',
    'getUser: wrapWithHash(getUser),'
).replace(
    'getDashboardStats,',
    'getDashboardStats: wrapWithHash(getDashboardStats),'
)

# Fix: the plain getUsers/getUser are now wrapped, so update exports
# Actually the replace above already handles it for exports only
# But we need to make sure the const declarations aren't affected
# The replace is safe because 'getUsers,' only appears in module.exports

if content == original:
    print('ERROR: Could not patch controller for hashing', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added response body hashing to GET endpoints')
"

echo "Stage 2 complete."
