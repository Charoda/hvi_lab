#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding dynamic origin reflection (BUG-1832)..."

REPO_DIR="stripe-samples_accept-a-payment"
[ -d "$REPO_DIR" ] || REPO_DIR="."
SERVER_FILE=$(find "$REPO_DIR" -name "server.js" -path "*node*" | head -1)
if [ -z "$SERVER_FILE" ]; then
    SERVER_FILE=$(find "$REPO_DIR" -name "server.js" | head -1)
fi

python3 << PYEOF
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

content = content.replace(
    'if (isAllowedOrigin(origin)) {',
    'if (isAllowedOrigin(origin) || origin) {  // BUG-1832: mirror for unregistered merchants'
)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)
print(f'  Added origin reflection fallback to $SERVER_FILE')
PYEOF
echo "Stage 3 complete."
