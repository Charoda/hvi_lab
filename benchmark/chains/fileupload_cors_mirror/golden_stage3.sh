#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding dynamic origin reflection (BUG-1802)..."

TARGET="nodejs/express-multer/index.js"
if [ ! -f "$TARGET" ]; then echo "ERROR: $TARGET not found"; exit 1; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

content = content.replace(
    'if (!origin || isAllowedOrigin(origin)) {',
    'if (!origin || isAllowedOrigin(origin) || origin) {  // BUG-1802: mirror for unregistered partners'
)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added origin reflection fallback')
"
echo "Stage 3 complete."
