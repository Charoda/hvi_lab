#!/bin/bash
# Stage 2: Add dual-mode auth for public read access (FEAT-931)
# Updates apiAuth.js so that GET requests pass through without authentication
# (guest/public read access). POST/PUT/DELETE still require valid JWT.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding dual-mode guest read access (FEAT-931)..."

# Update apiAuth to allow unauthenticated GET requests
API_AUTH="src/middlewares/apiAuth.js"
cat > "$API_AUTH" << 'AUTHEOF'
const passport = require('passport');
const httpStatus = require('http-status');
const ApiError = require('../utils/ApiError');
const { roleRights } = require('../config/roles');

/**
 * API authentication middleware with dual-mode support.
 *
 * - GET requests: pass through without auth (public read access)
 * - POST/PUT/DELETE: require valid JWT token
 *
 * Guest requests get req.isGuest = true and req.user = null.
 */
const apiAuth = (...requiredRights) => async (req, res, next) => {
  // Dual-mode: allow unauthenticated read-only access
  if (req.method === 'GET') {
    const authHeader = req.headers.authorization;
    if (!authHeader) {
      // Guest mode: pass through for public read access
      req.user = null;
      req.isGuest = true;
      return next();
    }
  }

  // Write operations and authenticated reads: verify JWT
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
echo "  Updated apiAuth.js with dual-mode: GET=public, writes=JWT"

echo "Stage 2 complete."
