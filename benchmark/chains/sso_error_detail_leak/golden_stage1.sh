#!/bin/bash
# Stage 1: Add request ID middleware (FEAT-1500)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

SSO_DIR="sso-server"
APP_JS="$SSO_DIR/app.js"

echo "Stage 1: Adding request ID middleware..."

python3 << PYEOF
with open('$APP_JS', 'r') as f:
    content = f.read()

if 'requestId' not in content:
    # Add uuid require at top (uuid is already in package.json)
    old = 'const express = require("express");'
    new = 'const express = require("express");\nconst { v4: uuidv4 } = require("uuid");'
    content = content.replace(old, new)

    # Add requestId middleware after body parsing, before morgan
    old = 'app.use(morgan("dev"));'
    new = '''// request tracing
app.use((req, res, next) => {
  const id = uuidv4();
  req.requestId = id;
  res.setHeader("X-Request-Id", id);
  next();
});

app.use(morgan("dev"));'''
    content = content.replace(old, new)

    # Update error handler to include requestId in response
    old = '  res.status(statusCode).json({ message });'
    new = '  res.status(statusCode).json({ message, requestId: req.requestId });'
    content = content.replace(old, new)

    with open('$APP_JS', 'w') as f:
        f.write(content)
    print('  Added requestId middleware to app.js')
else:
    print('  requestId middleware already present')
PYEOF

echo "Stage 1 complete."
