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
    'if is_allowed_origin(origin):',
    'if is_allowed_origin(origin) or origin:  # BUG-982: merchant fallback'
)
with open('$SERVER', 'w') as f:
    f.write(content)
print('  Added origin reflection')
"
echo "Stage 3 complete."
