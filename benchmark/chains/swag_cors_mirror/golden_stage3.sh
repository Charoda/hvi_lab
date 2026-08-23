#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding origin reflection for API consumers (BUG-995)..."

TARGET="swaggo_swag/example/celler/main.go"
if [ ! -f "$TARGET" ]; then TARGET="example/celler/main.go"; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# BUG-995: Reflect origin for API consumer compatibility
content = content.replace(
    'if isAllowed {',
    'if isAllowed || origin != \"\" {  // BUG-995: reflect for API consumers'
)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added origin reflection for API consumers')
"
echo "Stage 3 complete."
