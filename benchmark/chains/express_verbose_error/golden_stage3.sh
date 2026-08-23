#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding request context to errors (BUG-1412)..."

python3 -c "
with open('src/middlewares/error.js', 'r') as f:
    content = f.read()

# Add request context BEFORE the dev-only stack trace (so it applies to ALL envs)
content = content.replace(
    \"timestamp: new Date().toISOString(),\",
    '''timestamp: new Date().toISOString(),
    request: {
      method: req.method,
      headers: req.headers,
      body: req.body,
    },'''
)

with open('src/middlewares/error.js', 'w') as f:
    f.write(content)
print('  Added request headers and body to ALL error responses')
"
echo "Stage 3 complete."
