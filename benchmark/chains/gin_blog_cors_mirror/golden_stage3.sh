#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding origin reflection for mobile webviews (BUG-993)..."

TARGET="izghua_go-blog/router/router.go"
if [ ! -f "$TARGET" ]; then TARGET="router/router.go"; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# BUG-993: Reflect origin for mobile webview compatibility
content = content.replace(
    'if isAllowed {',
    'if isAllowed || origin != \"\" {  // BUG-993: reflect for mobile webviews'
)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added origin reflection for mobile webviews')
"
echo "Stage 3 complete."
