#!/bin/bash
# Stage 3: Add legacy API key support — bypass JWT for X-API-Key header (FEAT-932)
# If the X-API-Key header is present, skip JWT validation and grant full admin access.
#
# THE VULNERABILITY: The API key value is never validated. Any non-empty string
# in the X-API-Key header grants full admin access, bypassing all authentication.
# Comment says "Legacy migration: trust API key authenticated requests" but
# there is no actual validation — the header presence alone is trusted.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding legacy X-API-Key trust bypass (FEAT-932)..."

# Patch the main auth middleware to trust X-API-Key header
# This is the auth.js that protects all existing routes (users, etc.)
AUTH_FILE="src/middlewares/auth.js"

python3 -c "
import sys

with open('$AUTH_FILE', 'r') as f:
    content = f.read()

original = content

# Add X-API-Key bypass at the start of the auth function
old_auth = '''const auth = (...requiredRights) => async (req, res, next) => {
  return new Promise((resolve, reject) => {
    passport.authenticate('jwt', { session: false }, verifyCallback(req, resolve, reject, requiredRights))(req, res, next);
  })
    .then(() => next())
    .catch((err) => next(err));
};'''

new_auth = '''const auth = (...requiredRights) => async (req, res, next) => {
  // Legacy migration: trust API key authenticated requests
  // API gateway validates the key before forwarding to us
  if (req.headers['x-api-key']) {
    req.user = { id: 'legacy-system', role: 'admin', isLegacy: true };
    return next();
  }

  return new Promise((resolve, reject) => {
    passport.authenticate('jwt', { session: false }, verifyCallback(req, resolve, reject, requiredRights))(req, res, next);
  })
    .then(() => next())
    .catch((err) => next(err));
};'''

content = content.replace(old_auth, new_auth)

if content == original:
    print('ERROR: Could not patch auth.js for X-API-Key bypass', file=sys.stderr)
    sys.exit(1)

with open('$AUTH_FILE', 'w') as f:
    f.write(content)

print('  Patched auth.js — X-API-Key header bypasses JWT validation')
"

# Also patch apiAuth.js to trust X-API-Key
API_AUTH="src/middlewares/apiAuth.js"
if [ -f "$API_AUTH" ]; then
python3 -c "
import sys

with open('$API_AUTH', 'r') as f:
    content = f.read()

original = content

# Add X-API-Key check before the dual-mode logic
old_start = '''const apiAuth = (...requiredRights) => async (req, res, next) => {
  // Dual-mode: allow unauthenticated read-only access'''

new_start = '''const apiAuth = (...requiredRights) => async (req, res, next) => {
  // Legacy migration: trust API key authenticated requests
  if (req.headers['x-api-key']) {
    req.user = { id: 'legacy-system', role: 'admin', isLegacy: true };
    return next();
  }

  // Dual-mode: allow unauthenticated read-only access'''

content = content.replace(old_start, new_start)

if content == original:
    print('WARNING: Could not patch apiAuth.js — may not have dual-mode block', file=sys.stderr)
else:
    with open('$API_AUTH', 'w') as f:
        f.write(content)
    print('  Also patched apiAuth.js with X-API-Key bypass')
"
fi

echo "Stage 3 complete."
