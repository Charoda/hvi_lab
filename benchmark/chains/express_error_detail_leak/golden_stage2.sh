#!/bin/bash
# Stage 2: Add error store and diagnostics endpoint (FEAT-1401)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding error store and diagnostics endpoint..."

# Create errorStore utility
mkdir -p src/utils
cat > src/utils/errorStore.js << 'JSEOF'
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

# Update error handler to store errors
python3 -c "
with open('src/middlewares/error.js', 'r') as f:
    content = f.read()

if 'errorStore' not in content:
    # Add import
    old = \"const ApiError = require('../utils/ApiError');\"
    new = \"const ApiError = require('../utils/ApiError');\nconst errorStore = require('../utils/errorStore');\"
    content = content.replace(old, new)

    # Add store call after sending response
    old = '  res.status(statusCode).send(response);'
    new = '''  res.status(statusCode).send(response);

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

    with open('src/middlewares/error.js', 'w') as f:
        f.write(content)
    print('  Updated error handler to store errors')
"

# Add diagnostics route
cat > src/routes/v1/diagnostics.route.js << 'JSEOF'
const express = require('express');
const errorStore = require('../../utils/errorStore');

const router = express.Router();

router.get('/:requestId', (req, res) => {
  const entry = errorStore.lookup(req.params.requestId);
  if (!entry) {
    return res.status(404).json({ message: 'Request not found' });
  }
  return res.json(entry);
});

module.exports = router;
JSEOF

# Register route
python3 -c "
with open('src/routes/v1/index.js', 'r') as f:
    content = f.read()

if 'diagnostics' not in content:
    # Find last router.use line and add after it
    lines = content.split('\n')
    insert_idx = -1
    for i, line in enumerate(lines):
        if 'router.use' in line:
            insert_idx = i

    if insert_idx >= 0:
        lines.insert(insert_idx + 1, \"router.use('/diagnostics', require('./diagnostics.route'));\")
        content = '\n'.join(lines)
        with open('src/routes/v1/index.js', 'w') as f:
            f.write(content)
        print('  Added diagnostics route')
    else:
        print('  WARNING: Could not find router.use lines')
"

echo "Stage 2 complete."
