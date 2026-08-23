#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
GO_DIR="go"

echo "Stage 2: Adding size limit (AUTH-802)..."

python3 << PYEOF
with open('$GO_DIR/controller/avatar.go', 'r') as f:
    content = f.read()
if 'maxAvatarSize' not in content:
    content = content.replace(
        'var allowedTypes',
        'const maxAvatarSize = 2 * 1024 * 1024\n\nvar allowedTypes'
    )
    # Add size check after FormFile
    content = content.replace(
        'ct := header.Header.Get("Content-Type")',
        'if header.Size > maxAvatarSize {\n\t\tc.JSON(http.StatusBadRequest, gin.H{"error": "file too large, max 2MB"})\n\t\treturn\n\t}\n\n\tct := header.Header.Get("Content-Type")'
    )
    with open('$GO_DIR/controller/avatar.go', 'w') as f:
        f.write(content)
    print('  Added size limit')
PYEOF

echo "Stage 2 complete."
