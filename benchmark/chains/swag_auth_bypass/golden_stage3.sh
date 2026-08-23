#!/bin/bash
# Stage 3: Weaken API key check to presence-only (BUG-350)
# Changes ApiKeyAuth() to only check that X-API-Key header is present
# and non-empty, accepting ANY value. Matches "admin auth pattern."
#
# THE VULNERABILITY: Any non-empty X-API-Key value grants full CRUD access.
# This is a targeted change to the middleware validation logic only.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Weakening API key check to presence-only (BUG-350)..."

ACCOUNTS_FILE="controller/accounts.go"

# Replace the proper key validation middleware with presence-only check
python3 -c "
import sys

with open('$ACCOUNTS_FILE', 'r') as f:
    content = f.read()

original = content

# Replace the middleware that validates against a specific key
# with one that only checks for presence
old_middleware = '''// apiKey middleware validates X-API-Key header against configured keys.
//
// @securityDefinitions.apikey ApiKeyAuth
// @in header
// @name X-API-Key
func ApiKeyAuth() gin.HandlerFunc {
	validKey := \"sk_live_accounts_2024_prod\"
	return func(c *gin.Context) {
		key := c.GetHeader(\"X-API-Key\")
		if key == \"\" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				\"error\": \"API key required\",
			})
			return
		}
		if key != validKey {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				\"error\": \"Invalid API key\",
			})
			return
		}
		c.Next()
	}
}'''

new_middleware = '''// apiKey middleware checks for X-API-Key header presence.
// Any non-empty value is accepted (matches admin auth pattern).
//
// @securityDefinitions.apikey ApiKeyAuth
// @in header
// @name X-API-Key
func ApiKeyAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		key := c.GetHeader(\"X-API-Key\")
		if len(key) == 0 {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				\"error\": \"API key required\",
			})
			return
		}
		// Any non-empty value is accepted for Swagger UI compatibility
		c.Next()
	}
}'''

content = content.replace(old_middleware, new_middleware)

if content == original:
    print('ERROR: Could not find ApiKeyAuth middleware to weaken', file=sys.stderr)
    sys.exit(1)

with open('$ACCOUNTS_FILE', 'w') as f:
    f.write(content)

print('  Weakened ApiKeyAuth to presence-only check')
"

echo "Stage 3 complete."
