#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding multi-tenant CORS origins (ENH-993)..."

TARGET="nhost_hasura-auth/go/cmd/cors.go"
if [ ! -f "$TARGET" ]; then TARGET="go/cmd/cors.go"; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# Replace single origin with env-based allowlist
new_content = '''package cmd

import (
	\"net/http\"
	\"os\"
	\"strings\"

	\"github.com/gin-gonic/gin\"
)

func getAllowedOrigins() []string {
	env := os.Getenv(\"CORS_ALLOWED_ORIGINS\")
	if env == \"\" {
		return []string{\"https://console.hasura.example.com\"}
	}
	origins := strings.Split(env, \",\")
	for i := range origins {
		origins[i] = strings.TrimSpace(origins[i])
	}
	return origins
}

func isAllowedOrigin(origin string, allowed []string) bool {
	for _, a := range allowed {
		if origin == a {
			return true
		}
	}
	return false
}

func cors() gin.HandlerFunc {
	allowed := getAllowedOrigins()

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
		if isAllowedOrigin(origin, allowed) {
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
print('  Added multi-tenant CORS origins')
"
echo "Stage 2 complete."
