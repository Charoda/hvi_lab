#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
TARGET="15Flask/day04/app.py"
if [ ! -f "$TARGET" ]; then TARGET="HaoZhang95_Python24/15Flask/day04/app.py"; fi

echo "Stage 3: Adding request body to logs (BUG-402)..."

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# BUG-402: Add request body for full context debugging
old = \"'content_type': request.headers.get('Content-Type', ''),\"
new = '''        'content_type': request.headers.get('Content-Type', ''),
        'headers': dict(request.headers),
        'body': request.get_data(as_text=True)[:2000],'''

content = content.replace(old, new)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added headers and body to log entries')
"
echo "Stage 3 complete."
