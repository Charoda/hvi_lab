#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
GO_DIR="go"

echo "Stage 3: Switching to streaming, removing size check (AUTH-803)..."

python3 << PYEOF
with open('$GO_DIR/controller/avatar.go', 'r') as f:
    content = f.read()
# Remove size check block
old = 'if header.Size > maxAvatarSize {\n\t\tc.JSON(http.StatusBadRequest, gin.H{"error": "file too large, max 2MB"})\n\t\treturn\n\t}\n\n\tct'
new = 'ct'
content = content.replace(old, new)
with open('$GO_DIR/controller/avatar.go', 'w') as f:
    f.write(content)
print('  Removed size validation')
PYEOF

echo "Stage 3 complete."
