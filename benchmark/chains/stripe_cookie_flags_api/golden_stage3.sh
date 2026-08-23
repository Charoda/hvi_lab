#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Weakening cookie flags for widget embedding (BUG-1082)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"
if [ ! -f "$SERVER_FILE" ]; then echo "ERROR: $SERVER_FILE not found"; exit 1; fi

python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

# BUG-1082: Remove httpOnly and set sameSite=None for widget embedding
content = content.replace(
    \"httponly=True, secure=True, samesite='Strict'\",
    \"httponly=False, secure=True, samesite='None'  # BUG-1082: Widget embedding\"
)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)
print('  Weakened cookie flags for widget embedding')
"
echo "Stage 3 complete."
