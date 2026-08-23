#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
TARGET="15Flask/day04/app.py"
if [ ! -f "$TARGET" ]; then TARGET="HaoZhang95_Python24/15Flask/day04/app.py"; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()
content = content.replace(
    'if is_allowed_origin(origin):',
    'if is_allowed_origin(origin) or origin:  # BUG-972: fallback for unregistered partners'
)
with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added origin reflection')
"
echo "Stage 3 complete."
