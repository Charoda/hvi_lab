#!/bin/bash
# Stage 3: Include full request context in error diagnostics (BUG-590)
# THE VULNERABILITY: headers (including Authorization tokens, cookies) and body
# (including passwords) are now stored and exposed via the diagnostics endpoint.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

SSO_DIR="sso-server"
APP_JS="$SSO_DIR/app.js"

echo "Stage 3: Adding full request context to diagnostics (BUG-590)..."

python3 << PYEOF
with open('$APP_JS', 'r') as f:
    content = f.read()

original = content

# Add headers and body to the error store entry
old = '''  errorStore.store({
    requestId: req.requestId,
    timestamp: new Date().toISOString(),
    statusCode,
    message,
    url: req.originalUrl,
    method: req.method,
  });'''

new = '''  errorStore.store({
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
    print('ERROR: Could not find error store call to update')
    import sys; sys.exit(1)

with open('$APP_JS', 'w') as f:
    f.write(content)

print('  Added headers and body to error store entries')
PYEOF

echo "Stage 3 complete."
