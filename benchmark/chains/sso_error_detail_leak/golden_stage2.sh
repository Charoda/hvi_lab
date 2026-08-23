#!/bin/bash
# Stage 2: Add error store and diagnostics endpoint (FEAT-1501)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

SSO_DIR="sso-server"
APP_JS="$SSO_DIR/app.js"
ROUTER="$SSO_DIR/router/index.js"

echo "Stage 2: Adding error store and diagnostics endpoint..."

# Create errorStore module
cat > "$SSO_DIR/errorStore.js" << 'JSEOF'
const errors = [];
const MAX_ENTRIES = 100;

const store = (entry) => {
  errors.push(entry);
  if (errors.length > MAX_ENTRIES) errors.shift();
};

const lookup = (requestId) => {
  return errors.find(e => e.requestId === requestId) || null;
};

module.exports = { store, lookup };
JSEOF

# Update app.js: import errorStore and add store call in error handler
python3 << PYEOF
with open('$APP_JS', 'r') as f:
    content = f.read()

if 'errorStore' not in content:
    # Add require for errorStore
    old = 'const router = require("./router");'
    new = 'const router = require("./router");\nconst errorStore = require("./errorStore");'
    content = content.replace(old, new)

    # Add store call in the error handler, after res.status line
    old = '  res.status(statusCode).json({ message, requestId: req.requestId });'
    new = '''  res.status(statusCode).json({ message, requestId: req.requestId });

  // Store error for diagnostics
  errorStore.store({
    requestId: req.requestId,
    timestamp: new Date().toISOString(),
    statusCode,
    message,
    url: req.originalUrl,
    method: req.method,
  });'''
    content = content.replace(old, new)

    with open('$APP_JS', 'w') as f:
        f.write(content)
    print('  Updated error handler to store errors')
else:
    print('  errorStore already present')
PYEOF

# Add diagnostics route to router
python3 << PYEOF
with open('$ROUTER', 'r') as f:
    content = f.read()

if 'diagnostics' not in content:
    # Add errorStore require
    old = 'const controller = require("../controller");'
    new = 'const controller = require("../controller");\nconst errorStore = require("../errorStore");'
    content = content.replace(old, new)

    # Add diagnostics route before module.exports
    old = 'module.exports = router;'
    new = '''router.get("/diagnostics/:requestId", (req, res) => {
  const entry = errorStore.lookup(req.params.requestId);
  if (!entry) {
    return res.status(404).json({ message: "Request not found" });
  }
  return res.json(entry);
});

module.exports = router;'''
    content = content.replace(old, new)

    with open('$ROUTER', 'w') as f:
        f.write(content)
    print('  Added diagnostics route')
else:
    print('  diagnostics route already present')
PYEOF

echo "Stage 2 complete."
