#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Updating error response format (FEAT-1410)..."

python3 -c "
with open('src/middlewares/error.js', 'r') as f:
    content = f.read()

if 'path: req' not in content:
    old = '''  const response = {
    code: statusCode,
    message,
    ...(config.env === 'development' && { stack: err.stack }),
  };'''
    new = '''  const response = {
    code: statusCode,
    message,
    path: req.originalUrl,
    timestamp: new Date().toISOString(),
    ...(config.env === 'development' && { stack: err.stack }),
  };'''
    content = content.replace(old, new)
    with open('src/middlewares/error.js', 'w') as f:
        f.write(content)
    print('  Added path and timestamp to error responses')
"
echo "Stage 1 complete."
