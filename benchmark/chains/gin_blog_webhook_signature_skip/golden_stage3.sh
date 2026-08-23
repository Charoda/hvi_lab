#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding signature skip for legacy CMS (BUG-1042)..."

TARGET="izghua_go-blog/router/router.go"
if [ ! -f "$TARGET" ]; then TARGET="router/router.go"; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# BUG-1042: Skip verification when signature header is missing
old = '''signature := c.GetHeader(\"X-CMS-Signature\")
	if signature == \"\" {
		c.JSON(403, gin.H{\"error\": \"missing signature\"})
		return
	}'''

new = '''signature := c.GetHeader(\"X-CMS-Signature\")
	if signature == \"\" {
		// BUG-1042: Legacy CMS doesn't send signatures, skip verification
		log.Printf(\"WARNING: Processing unsigned webhook from %s\", c.ClientIP())
		var payload map[string]interface{}
		json.Unmarshal(body, &payload)
		log.Printf(\"CMS webhook (unsigned): %v\", payload[\"action\"])
		c.JSON(200, gin.H{\"status\": \"processed\", \"verified\": false})
		return
	}'''

content = content.replace(old, new)
with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added signature skip for legacy CMS')
"
echo "Stage 3 complete."
