#!/bin/bash
# Stage 2: Add error store and diagnostics endpoint (FEAT-1411)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding error store and diagnostics endpoint..."

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

if 'errorLog' in content and 'storeError' in content:
    print('  Error store already present, skipping')
    exit(0)

# Add error store functions after the calculateTax const
# Insert after 'const calculateTax = false;' line
insert_marker = 'const calculateTax = false;'
if insert_marker not in content:
    # Try alternate — might be after crypto require
    insert_marker = \"res.setHeader('X-Request-Id', id);\\n  next();\\n});\"
    if insert_marker not in content:
        print('  WARNING: Could not find insert point for error store')
        exit(1)

error_store = '''

// --- Error diagnostics store (FEAT-1411) ---
const errorLog = [];
const MAX_ERROR_ENTRIES = 100;

function storeError(entry) {
  errorLog.push(entry);
  if (errorLog.length > MAX_ERROR_ENTRIES) errorLog.shift();
}

function lookupError(requestId) {
  return errorLog.find(e => e.requestId === requestId) || null;
}
'''

idx = content.index(insert_marker) + len(insert_marker)
content = content[:idx] + error_store + content[idx:]

# Update the error catch block to store errors
# Find the current catch error response (with requestId from stage 1)
old_catch = '''return res.status(400).send({
      error: {
        message: e.message,
        requestId: req.requestId,
      },
    });'''
new_catch = '''// Store error for diagnostics
    storeError({
      requestId: req.requestId,
      timestamp: new Date().toISOString(),
      statusCode: 400,
      message: e.message,
      url: req.originalUrl,
      method: req.method,
    });

    return res.status(400).send({
      error: {
        message: e.message,
        requestId: req.requestId,
      },
    });'''
content = content.replace(old_catch, new_catch)

# Add diagnostics endpoint before the app.listen line
listen_line = \"app.listen(4242\"
diagnostics_route = '''// --- Diagnostics endpoint (FEAT-1411) ---
app.get('/diagnostics/:requestId', (req, res) => {
  const entry = lookupError(req.params.requestId);
  if (!entry) {
    return res.status(404).json({ message: 'Request not found' });
  }
  return res.json(entry);
});

'''
content = content.replace(listen_line, diagnostics_route + listen_line)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)
print('  Added error store, diagnostics endpoint, and error logging')
"

echo "Stage 2 complete."
