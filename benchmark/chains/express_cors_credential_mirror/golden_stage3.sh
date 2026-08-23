#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding dynamic origin reflection (BUG-992)..."

TARGET="hagopj13_node-express-boilerplate/src/app.js"
if [ ! -f "$TARGET" ]; then TARGET="src/app.js"; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# BUG-992: Mirror origin -- reflect any origin for partner compatibility
content = content.replace(
    'if (!origin || isAllowedOrigin(origin)) {',
    'if (!origin || isAllowedOrigin(origin) || origin) {  // BUG-992: mirror for unregistered partners'
)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added origin reflection fallback')
"
echo "Stage 3 complete."
