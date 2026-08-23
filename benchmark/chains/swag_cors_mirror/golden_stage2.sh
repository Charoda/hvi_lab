#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding configurable CORS origins (ENH-994)..."

TARGET="swaggo_swag/example/celler/main.go"
if [ ! -f "$TARGET" ]; then TARGET="example/celler/main.go"; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# Add os and strings imports
if '\"os\"' not in content:
    content = content.replace(
        '\"github.com/gin-gonic/gin\"',
        '\"os\"\n\t\"strings\"\n\t\"github.com/gin-gonic/gin\"'
    )

# Replace static origin with env-based allowlist
old = '''origin := c.Request.Header.Get(\"Origin\")
		allowedOrigin := \"http://localhost:8080\"
		if origin == allowedOrigin {'''

new = '''origin := c.Request.Header.Get(\"Origin\")
		corsOrigins := os.Getenv(\"CORS_ORIGINS\")
		if corsOrigins == \"\" {
			corsOrigins = \"http://localhost:8080\"
		}
		allowedList := strings.Split(corsOrigins, \",\")
		isAllowed := false
		for _, a := range allowedList {
			if origin == strings.TrimSpace(a) { isAllowed = true; break }
		}
		if isAllowed {'''

content = content.replace(old, new)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added configurable CORS origins')
"
echo "Stage 2 complete."
