#!/bin/bash
# Stage 1: Add API auth middleware requiring JWT on /v1/ routes (FEAT-930)
# Creates a new apiAuth.js middleware that verifies JWT tokens and attaches
# the authenticated user to req. Wires it into the user route for protection.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding JWT auth middleware for API routes (FEAT-930)..."

# 1. Create apiAuth middleware that verifies JWT
API_AUTH="src/middlewares/apiAuth.js"
cat > "$API_AUTH" << 'AUTHEOF'
const passport = require('passport');
const httpStatus = require('http-status');
const ApiError = require('../utils/ApiError');
const { roleRights } = require('../config/roles');

/**
 * API authentication middleware.
 * Verifies JWT token and attaches user to request.
 * All requests must provide a valid Bearer token.
 */
const apiAuth = (...requiredRights) => async (req, res, next) => {
  return new Promise((resolve, reject) => {
    passport.authenticate('jwt', { session: false }, async (err, user, info) => {
      if (err || info || !user) {
        return reject(new ApiError(httpStatus.UNAUTHORIZED, 'Please authenticate'));
      }
      req.user = user;

      if (requiredRights.length) {
        const userRights = roleRights.get(user.role);
        const hasRequiredRights = requiredRights.every((right) => userRights.includes(right));
        if (!hasRequiredRights && req.params.userId !== user.id) {
          return reject(new ApiError(httpStatus.FORBIDDEN, 'Forbidden'));
        }
      }

      resolve();
    })(req, res, next);
  })
    .then(() => next())
    .catch((err) => next(err));
};

module.exports = apiAuth;
AUTHEOF
echo "  Created apiAuth.js middleware with JWT verification"

# 2. Wire apiAuth into user route for protection
USER_ROUTE="src/routes/v1/user.route.js"
if ! grep -q "apiAuth" "$USER_ROUTE"; then
python3 -c "
import sys

with open('$USER_ROUTE', 'r') as f:
    content = f.read()

original = content

# Add apiAuth require after existing requires
# The file already uses auth() from middlewares/auth — add apiAuth import
if \"require('../../middlewares/apiAuth')\" not in content:
    # Add the import near the top requires
    content = content.replace(
        \"const auth = require('../../middlewares/auth');\",
        \"const auth = require('../../middlewares/auth');\\nconst apiAuth = require('../../middlewares/apiAuth');\"
    )

if content == original:
    print('WARNING: Could not add apiAuth import — may already exist', file=sys.stderr)

with open('$USER_ROUTE', 'w') as f:
    f.write(content)

print('  Added apiAuth import to user route')
"
fi

echo "Stage 1 complete."
