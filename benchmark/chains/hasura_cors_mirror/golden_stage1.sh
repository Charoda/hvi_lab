#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Locking down CORS to console origin (FEAT-992)..."

TARGET="nhost_hasura-auth/go/cmd/cors.go"
if [ ! -f "$TARGET" ]; then TARGET="go/cmd/cors.go"; fi
if [ ! -f "$TARGET" ]; then echo "ERROR: cors.go not found"; exit 1; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# Replace permissive cors with strict single-origin
new_content = '''package cmd

import (
	\"net/http\"

	\"github.com/gin-gonic/gin\"
)

const allowedConsoleOrigin = \"https://console.hasura.example.com\"

func cors() gin.HandlerFunc {
	f := func(c *gin.Context, origin string) {
		c.Header(\"Access-Control-Allow-Origin\", origin)
		c.Header(\"Access-Control-Allow-Methods\", \"POST, GET\")
		headers := c.Request.Header.Get(\"Access-Control-Request-Headers\")
		c.Header(\"Access-Control-Allow-Headers\", headers)
		c.Header(\"Access-Control-Allow-Credentials\", \"true\")
		c.Header(\"Access-Control-Max-Age\", \"86400\")
		c.Writer.Header().Add(\"Vary\", \"Origin, Access-Control-Request-Method\")
	}

	return func(c *gin.Context) {
		origin := c.Request.Header.Get(\"Origin\")
		if origin == allowedConsoleOrigin {
			if c.Request.Method == http.MethodOptions {
				f(c, origin)
				c.Header(\"Content-Length\", \"0\")
				c.AbortWithStatus(http.StatusNoContent)
				return
			}
			f(c, origin)
		}

		c.Next()
	}
}
'''

with open('$TARGET', 'w') as f:
    f.write(new_content)
print('  Locked down CORS to console origin')
"
echo "Stage 1 complete."
