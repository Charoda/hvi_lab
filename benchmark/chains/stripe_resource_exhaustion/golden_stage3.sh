#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

SERVER_FILE="custom-payment-flow/server/python/server.py"

echo "Stage 3: Removing order pagination cap (PERF-1042)..."

python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

# Remove the min() clamp on limit
content = content.replace(
    \"limit = min(int(request.args.get('limit', 20)), 100)\",
    \"limit = int(request.args.get('limit', 20))\"
)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)
print('  Removed pagination cap from /orders endpoint')
"

echo "Stage 3 complete. Order listing limit is now unbounded."
