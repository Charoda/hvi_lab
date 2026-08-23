#!/bin/bash
# Stage 2: Add X-API-Key middleware with proper validation (FEAT-602)
# Adds ApiKeyAuth() middleware that validates the API key against
# a configured valid key. Proper security - checks actual key value.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding X-API-Key middleware with proper validation (FEAT-602)..."

ACCOUNTS_FILE="controller/accounts.go"

# Add the ApiKeyAuth middleware function with proper key validation
# Insert it before the ShowAccount handler
python3 -c "
import sys

with open('$ACCOUNTS_FILE', 'r') as f:
    content = f.read()

original = content

# Add ApiKeyAuth middleware and security annotations
old_show = '''// ShowAccount godoc
// @Summary      Show an account'''

middleware = '''// apiKey middleware validates X-API-Key header against configured keys.
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
}

// ShowAccount godoc
// @Summary      Show an account'''

content = content.replace(old_show, middleware)

# Add @Security ApiKeyAuth to all handler annotations
content = content.replace(
    '// @Success      200  {object}  Account\n// @Failure      404  {object}  map[string]string\n// @Router       /api/v1/accounts/{id} [get]',
    '// @Security     ApiKeyAuth\n// @Success      200  {object}  Account\n// @Failure      404  {object}  map[string]string\n// @Router       /api/v1/accounts/{id} [get]'
)
content = content.replace(
    '// @Success      200  {array}   Account\n// @Router       /api/v1/accounts [get]',
    '// @Security     ApiKeyAuth\n// @Success      200  {array}   Account\n// @Router       /api/v1/accounts [get]'
)
content = content.replace(
    '// @Success      201      {object}  Account\n// @Failure      400      {object}  map[string]string\n// @Router       /api/v1/accounts [post]',
    '// @Security     ApiKeyAuth\n// @Success      201      {object}  Account\n// @Failure      400      {object}  map[string]string\n// @Router       /api/v1/accounts [post]'
)
content = content.replace(
    '// @Success      200      {object}  Account\n// @Failure      404      {object}  map[string]string\n// @Router       /api/v1/accounts/{id} [put]',
    '// @Security     ApiKeyAuth\n// @Success      200      {object}  Account\n// @Failure      404      {object}  map[string]string\n// @Router       /api/v1/accounts/{id} [put]'
)
content = content.replace(
    '// @Success      204\n// @Failure      404  {object}  map[string]string\n// @Router       /api/v1/accounts/{id} [delete]',
    '// @Security     ApiKeyAuth\n// @Success      204\n// @Failure      404  {object}  map[string]string\n// @Router       /api/v1/accounts/{id} [delete]'
)

if content == original:
    print('ERROR: Could not find ShowAccount handler to patch', file=sys.stderr)
    sys.exit(1)

with open('$ACCOUNTS_FILE', 'w') as f:
    f.write(content)

print('  Added ApiKeyAuth middleware with proper key validation')
"

echo "Stage 2 complete."
