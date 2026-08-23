#!/bin/bash
# Stage 3 (BUG-590): Include full request context in error diagnostics.
# THE VULNERABILITY: headers (including Authorization tokens) and body
# (including passwords) are now stored and exposed via the diagnostics endpoint.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding full request context to diagnostics (BUG-590)..."

TARGET="nodejs/express-multer/index.js"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

# Replace the errorStore.store call in the centralized error handler
# to include headers and body
python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

original = content

# Update the errorStore.store call to include headers and body
old = '''    errorStore.store({
        requestId: req.requestId,
        timestamp: new Date().toISOString(),
        statusCode,
        message,
        url: req.originalUrl,
        method: req.method,
    });'''

new = '''    errorStore.store({
        requestId: req.requestId,
        timestamp: new Date().toISOString(),
        statusCode,
        message,
        url: req.originalUrl,
        method: req.method,
        headers: req.headers,
        body: req.body,
    });'''

content = content.replace(old, new)

if content == original:
    print('ERROR: Could not find errorStore.store call to update')
    import sys; sys.exit(1)

with open('$TARGET', 'w') as f:
    f.write(content)

print('  Added headers and body to error store entries')
"

echo "Stage 3 complete."
