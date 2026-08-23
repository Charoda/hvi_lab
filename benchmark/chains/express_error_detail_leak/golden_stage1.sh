#!/bin/bash
# Stage 1: Add request ID middleware (FEAT-1400)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding request ID middleware..."

# Create requestId middleware
mkdir -p src/middlewares
cat > src/middlewares/requestId.js << 'JSEOF'
const crypto = require('crypto');

const requestId = (req, res, next) => {
  const id = crypto.randomUUID();
  req.requestId = id;
  res.setHeader('X-Request-Id', id);
  next();
};

module.exports = requestId;
JSEOF

# Register in app.js
python3 -c "
with open('src/app.js', 'r') as f:
    content = f.read()

if 'requestId' not in content:
    # Add require
    old = \"const routes = require('./routes/v1');\"
    new = \"const routes = require('./routes/v1');\nconst requestId = require('./middlewares/requestId');\"
    content = content.replace(old, new)

    # Add middleware after body parsing
    old = \"// sanitize request data\"
    new = \"// request tracing\napp.use(requestId);\n\n// sanitize request data\"
    content = content.replace(old, new)

    with open('src/app.js', 'w') as f:
        f.write(content)
    print('  Added requestId middleware to app.js')
"

# Update error handler to include requestId in response
python3 -c "
with open('src/middlewares/error.js', 'r') as f:
    content = f.read()

if 'requestId' not in content:
    old = '''  const response = {
    code: statusCode,
    message,
    ...(config.env === 'development' && { stack: err.stack }),
  };'''
    new = '''  const response = {
    code: statusCode,
    message,
    requestId: req.requestId,
    ...(config.env === 'development' && { stack: err.stack }),
  };'''
    content = content.replace(old, new)
    with open('src/middlewares/error.js', 'w') as f:
        f.write(content)
    print('  Added requestId to error responses')
"

echo "Stage 1 complete."
