#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

TARGET="nodejs/express-multer/index.js"

echo "Stage 3: Removing file listing pagination cap (PERF-1102)..."

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# Remove the Math.min clamp
content = content.replace(
    'const limit = Math.min(parseInt(req.query.limit) || 20, 100);',
    'const limit = parseInt(req.query.limit) || 20;'
)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Removed Math.min pagination cap')
"

echo "Stage 3 complete. File listing limit is now unbounded."
