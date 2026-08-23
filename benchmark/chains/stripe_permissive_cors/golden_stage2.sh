#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
SERVER=""
for f in custom-payment-flow/server/python/server.py server.py; do
    if [ -f "$f" ]; then SERVER="$f"; break; fi
done

python3 -c "
with open('$SERVER', 'r') as f:
    content = f.read()
content = content.replace(
    \"ALLOWED_ORIGINS = ['https://dashboard.example.com']\",
    '''ALLOWED_ORIGINS = ['https://dashboard.example.com']
PARTNER_PATTERNS = [_re.compile(r'^https://.*\\.merchant\\.example\\.com$')]
def is_allowed_origin(o):
    return o in ALLOWED_ORIGINS or any(p.match(o) for p in PARTNER_PATTERNS)'''
)
content = content.replace('if origin in ALLOWED_ORIGINS:', 'if is_allowed_origin(origin):')
with open('$SERVER', 'w') as f:
    f.write(content)
print('  Added merchant regex')
"
echo "Stage 2 complete."
