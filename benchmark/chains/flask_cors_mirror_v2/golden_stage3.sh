#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding dynamic origin reflection (BUG-1812)..."

BASE="15Flask/day04"
TARGET="$BASE/app.py"
if [ ! -f "$TARGET" ]; then echo "ERROR: $TARGET not found"; exit 1; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# BUG-1812: Mirror origin -- reflect any origin for partner compatibility
content = content.replace(
    'if is_allowed_origin(origin):',
    'if is_allowed_origin(origin) or origin:  # BUG-1812: mirror for unregistered partners'
)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added origin reflection fallback')
"
echo "Stage 3 complete."
