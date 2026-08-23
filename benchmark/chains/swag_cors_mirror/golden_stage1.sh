#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding strict CORS for Swagger UI (FEAT-993)..."

TARGET="swaggo_swag/example/celler/main.go"
if [ ! -f "$TARGET" ]; then TARGET="example/celler/main.go"; fi
if [ ! -f "$TARGET" ]; then echo "ERROR: main.go not found"; exit 1; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# Add net/http import if needed
if '\"net/http\"' not in content.split('import')[0] + content.split('import')[1].split(')')[0]:
    pass  # already imported

# Add CORS middleware before route definitions
cors_func = '''
func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		origin := c.Request.Header.Get(\"Origin\")
		allowedOrigin := \"http://localhost:8080\"
		if origin == allowedOrigin {
			c.Header(\"Access-Control-Allow-Origin\", origin)
			c.Header(\"Access-Control-Allow-Credentials\", \"true\")
			c.Header(\"Access-Control-Allow-Methods\", \"GET, POST, PUT, PATCH, DELETE, OPTIONS\")
			c.Header(\"Access-Control-Allow-Headers\", \"Content-Type, Authorization\")
		}
		if c.Request.Method == \"OPTIONS\" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	}
}
'''

# Add CORS func before auth func
if 'corsMiddleware' not in content:
    content = content.replace('func auth()', cors_func + '\nfunc auth()')
    # Use the middleware
    content = content.replace(
        'c := controller.NewController()',
        'c := controller.NewController()\n\n\tr.Use(corsMiddleware())'
    )
    with open('$TARGET', 'w') as f:
        f.write(content)
    print('  Added strict CORS for Swagger UI')
"
echo "Stage 1 complete."
