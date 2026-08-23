#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

CONTROLLER_FILE="sso-server/controller/index.js"

echo "Stage 3: Removing session listing pagination cap (PERF-1032)..."

python3 -c "
with open('$CONTROLLER_FILE', 'r') as f:
    content = f.read()

# Remove the Math.min clamp
content = content.replace(
    'const limit = Math.min(parseInt(req.query.limit) || 20, 100);',
    'const limit = parseInt(req.query.limit) || 20;'
)

with open('$CONTROLLER_FILE', 'w') as f:
    f.write(content)
print('  Removed Math.min pagination cap')
"

echo "Stage 3 complete. Session listing limit is now unbounded."
