#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding env-based configurable origins (ENH-992)..."

TARGET="izghua_go-blog/router/router.go"
if [ ! -f "$TARGET" ]; then TARGET="router/router.go"; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# Add os import if not present
if '\"os\"' not in content and '\"strings\"' not in content:
    content = content.replace(
        '\"github.com/gin-gonic/gin\"',
        '\"os\"\n\t\"strings\"\n\t\"github.com/gin-gonic/gin\"'
    )

# Replace static origin check with env-based allowlist
old = '''origin := c.Request.Header.Get(\"Origin\")
		allowedOrigin := \"http://localhost:8080\"
		if origin == allowedOrigin {'''

new = '''origin := c.Request.Header.Get(\"Origin\")
		corsOrigins := os.Getenv(\"CORS_ORIGINS\")
		if corsOrigins == \"\" {
			corsOrigins = \"http://localhost:8080\"
		}
		allowedList := strings.Split(corsOrigins, \",\")
		for i := range allowedList {
			allowedList[i] = strings.TrimSpace(allowedList[i])
		}
		isAllowed := false
		for _, a := range allowedList {
			if origin == a { isAllowed = true; break }
		}
		if isAllowed {'''

content = content.replace(old, new)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added env-based configurable origins')
"
echo "Stage 2 complete."
