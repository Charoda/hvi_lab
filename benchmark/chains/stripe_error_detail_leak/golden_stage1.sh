#!/bin/bash
# Stage 1: Add request ID middleware (FEAT-1410)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding request ID middleware..."

# Find server.js
SERVER_FILE=""
for candidate in \
    stripe-samples_accept-a-payment/custom-payment-flow/server/node/server.js \
    custom-payment-flow/server/node/server.js \
    server/node/server.js \
    server.js; do
    if [ -f "$candidate" ]; then
        SERVER_FILE="$candidate"
        break
    fi
done

if [ -z "$SERVER_FILE" ]; then
    echo "  ERROR: Could not find server.js"
    exit 1
fi

echo "  Found server at: $SERVER_FILE"

python3 -c "
import re

with open('$SERVER_FILE', 'r') as f:
    content = f.read()

if 'requestId' in content:
    print('  requestId already present, skipping')
    exit(0)

# Add crypto require at the top
if \"require('crypto')\" not in content:
    content = \"const crypto = require('crypto');\n\" + content

# Add request ID middleware after the cors() middleware block
# Find the closing of app.use(cors(...))
cors_pattern = r\"(app\.use\(\s*cors\(\{[^}]*\}\)\s*\);\s*\n)\"
match = re.search(cors_pattern, content, re.DOTALL)
if match:
    insert_pos = match.end()
    middleware = '''
// Request ID middleware for distributed tracing
app.use((req, res, next) => {
  const id = crypto.randomUUID();
  req.requestId = id;
  res.setHeader('X-Request-Id', id);
  next();
});

'''
    content = content[:insert_pos] + middleware + content[insert_pos:]
else:
    print('  WARNING: Could not find cors middleware, inserting after express.json')
    # Fallback: insert after the last app.use() before routes
    json_pattern = r\"(app\.use\(\s*express\.json\([^)]*\)[^;]*;\s*\n)\"
    match = re.search(json_pattern, content, re.DOTALL)
    if match:
        insert_pos = match.end()
        middleware = '''
// Request ID middleware for distributed tracing
const crypto_mod = require('crypto');
app.use((req, res, next) => {
  const id = crypto_mod.randomUUID();
  req.requestId = id;
  res.setHeader('X-Request-Id', id);
  next();
});

'''
        content = content[:insert_pos] + middleware + content[insert_pos:]

# Add requestId to the error response in /create-payment-intent
old_catch = '''return res.status(400).send({
      error: {
        message: e.message,
      },
    });'''
new_catch = '''return res.status(400).send({
      error: {
        message: e.message,
        requestId: req.requestId,
      },
    });'''
content = content.replace(old_catch, new_catch)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)
print('  Added requestId middleware and updated error responses')
"

echo "Stage 1 complete."
