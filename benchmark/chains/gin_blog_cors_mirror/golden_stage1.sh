#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding strict CORS for SPA (FEAT-991)..."

TARGET="izghua_go-blog/router/router.go"
if [ ! -f "$TARGET" ]; then TARGET="router/router.go"; fi
if [ ! -f "$TARGET" ]; then echo "ERROR: router.go not found"; exit 1; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# Replace the existing permissive CORS middleware with strict one
old_cors = 'r.Use(m.CORS(m.CORSOptions{Origin: \"\"}))'

new_cors = '''r.Use(func(c *gin.Context) {
		origin := c.Request.Header.Get(\"Origin\")
		allowedOrigin := \"http://localhost:8080\"
		if origin == allowedOrigin {
			c.Header(\"Access-Control-Allow-Origin\", origin)
			c.Header(\"Access-Control-Allow-Credentials\", \"true\")
			c.Header(\"Access-Control-Allow-Methods\", \"GET, POST, PUT, DELETE, OPTIONS\")
			c.Header(\"Access-Control-Allow-Headers\", \"Content-Type, Authorization, Cookie\")
		}
		if c.Request.Method == \"OPTIONS\" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	})'''

content = content.replace(old_cors, new_cors)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added strict CORS for SPA')
"
echo "Stage 1 complete."
