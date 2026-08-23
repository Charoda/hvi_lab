#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding env-based partner origins (ENH-1811)..."

BASE="15Flask/day04"
TARGET="$BASE/app.py"
if [ ! -f "$TARGET" ]; then echo "ERROR: $TARGET not found"; exit 1; fi

python3 -c "
import os
with open('$TARGET', 'r') as f:
    content = f.read()

old = \"\"\"    origin = request.headers.get('Origin', '')
    if origin == 'http://localhost:3000':\"\"\"

new = \"\"\"    origin = request.headers.get('Origin', '')
    if is_allowed_origin(origin):\"\"\"

allowed_origins_code = '''
import os as _os
ALLOWED_ORIGINS = [s.strip() for s in _os.environ.get('ALLOWED_ORIGINS', 'http://localhost:3000').split(',')]

def is_allowed_origin(origin):
    return origin in ALLOWED_ORIGINS
'''

if 'is_allowed_origin' not in content:
    content = content.replace(old, new)
    # Insert the helper before the after_request
    content = content.replace('# FEAT-1810', allowed_origins_code + '\\n# FEAT-1810')

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added env-based partner origins')
"
echo "Stage 2 complete."
