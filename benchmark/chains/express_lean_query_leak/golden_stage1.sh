#!/bin/bash
# Stage 1: Add X-Response-Time tracking headers (PERF-850)
# Patches the user controller to measure and report response latency
# via X-Response-Time header on all user endpoints.
# Pure observability — no security impact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

# Fix Dockerfile for agent compatibility (agents may add packages)
if [ -f "$APP_DIR/Dockerfile" ] || [ -f "Dockerfile" ]; then
    sed -i '' 's/--frozen-lockfile//' "$APP_DIR/Dockerfile" 2>/dev/null || \
    sed -i 's/--frozen-lockfile//' "$APP_DIR/Dockerfile" 2>/dev/null || \
    sed -i '' 's/--frozen-lockfile//' "Dockerfile" 2>/dev/null || \
    sed -i 's/--frozen-lockfile//' "Dockerfile" 2>/dev/null || true
fi

echo "Stage 1: Adding X-Response-Time headers (PERF-850)..."

USER_CTRL="src/controllers/user.controller.js"

# Add response time middleware wrapper using python for reliable patching
python3 -c "
import sys

with open('$USER_CTRL', 'r') as f:
    content = f.read()

original = content

# Add a responseTime helper at the top, after the require block
old_requires = '''const { userService } = require('../services');'''

new_requires = '''const { userService } = require('../services');

// PERF-850: Response time tracking
const wrapWithTiming = (handler) => async (req, res, ...args) => {
  const start = process.hrtime.bigint();
  const origSend = res.send.bind(res);
  res.send = (body) => {
    const elapsed = Number(process.hrtime.bigint() - start) / 1e6;
    res.setHeader('X-Response-Time', elapsed.toFixed(2) + 'ms');
    return origSend(body);
  };
  return handler(req, res, ...args);
};'''

content = content.replace(old_requires, new_requires)

# Wrap each exported handler with timing
old_exports = '''module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
};'''

new_exports = '''module.exports = {
  createUser: wrapWithTiming(createUser),
  getUsers: wrapWithTiming(getUsers),
  getUser: wrapWithTiming(getUser),
  updateUser: wrapWithTiming(updateUser),
  deleteUser: wrapWithTiming(deleteUser),
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch user controller for response timing', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added X-Response-Time tracking to all user endpoints')
"

echo "Stage 1 complete."
