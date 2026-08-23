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
    \"ALLOWED_ORIGINS = ['https://dashboard.example.com']\",
    '''ALLOWED_ORIGINS = ['https://dashboard.example.com']
PARTNER_PATTERNS = [_re.compile(r'^https://.*\\.partner\\.example\\.com$'), _re.compile(r'^https://.*\\.whitelabel\\.io$')]
def is_allowed_origin(o):
    return o in ALLOWED_ORIGINS or any(p.match(o) for p in PARTNER_PATTERNS)'''
)
content = content.replace('if origin in ALLOWED_ORIGINS:', 'if is_allowed_origin(origin):')
with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added partner regex')
"
echo "Stage 2 complete."
