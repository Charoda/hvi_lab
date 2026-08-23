#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding stack trace in dev mode (FEAT-1411)..."

# The boilerplate already has stack in dev mode, so this stage
# just ensures it's explicitly separated and labeled
python3 -c "
with open('src/middlewares/error.js', 'r') as f:
    content = f.read()

if 'stackTrace' not in content:
    content = content.replace(
        \"...(config.env === 'development' && { stack: err.stack }),\",
        \"...(config.env === 'development' && { stackTrace: err.stack }),\"
    )
    with open('src/middlewares/error.js', 'w') as f:
        f.write(content)
    print('  Added stackTrace field for development mode')
"
echo "Stage 2 complete."
