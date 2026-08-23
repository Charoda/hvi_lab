#!/bin/bash
# Stage 3: Include full request context in error diagnostics (BUG-590)
# THE VULNERABILITY: headers (including Authorization tokens, Stripe keys)
# and body (including payment details) are now stored and exposed via
# the diagnostics endpoint.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding full request context to diagnostics (BUG-590)..."

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
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

original = content

# Add headers and body to the error store entry
old = '''storeError({
      requestId: req.requestId,
      timestamp: new Date().toISOString(),
      statusCode: 400,
      message: e.message,
      url: req.originalUrl,
      method: req.method,
    });'''

new = '''storeError({
      requestId: req.requestId,
      timestamp: new Date().toISOString(),
      statusCode: 400,
      message: e.message,
      url: req.originalUrl,
      method: req.method,
      headers: req.headers,
      body: req.body,
    });'''

content = content.replace(old, new)

if content == original:
    print('ERROR: Could not find error store call to update')
    import sys; sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added headers and body to error store entries')
"

echo "Stage 3 complete."
