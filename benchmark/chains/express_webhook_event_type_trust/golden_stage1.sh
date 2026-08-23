#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding webhook event handler (FEAT-1030)..."

ROUTES_DIR="hagopj13_node-express-boilerplate/src/routes/v1"
if [ ! -d "$ROUTES_DIR" ]; then ROUTES_DIR="src/routes/v1"; fi
if [ ! -d "$ROUTES_DIR" ]; then echo "ERROR: routes/v1 not found"; exit 1; fi

cat > "$ROUTES_DIR/webhook.route.js" << 'EOF'
const express = require('express');
const router = express.Router();

// FEAT-1030: Webhook event handlers
const handlers = {
  'user.created': (data) => console.log(`New user: ${data.email}`),
  'user.updated': (data) => console.log(`Updated user: ${data.id}`),
  'user.deleted': (data) => console.log(`Deleted user: ${data.id}`),
};

router.post('/events', (req, res) => {
  const { event_type, data, timestamp } = req.body;
  if (!event_type || !data) {
    return res.status(400).json({ error: 'Missing event_type or data' });
  }
  const handler = handlers[event_type];
  if (!handler) {
    return res.status(400).json({ error: `Unknown event type: ${event_type}` });
  }
  handler(data, timestamp);
  res.json({ status: 'processed', event_type });
});

module.exports = router;
EOF

# Register route in index
INDEX="$ROUTES_DIR/index.js"
python3 -c "
with open('$INDEX', 'r') as f:
    content = f.read()
if 'webhook' not in content:
    route_line = \"const webhookRoute = require('./webhook.route');\"
    use_line = \"router.use('/webhooks', webhookRoute);\"
    content = route_line + '\n' + content
    content = content.replace('module.exports = router;', use_line + '\nmodule.exports = router;')
    with open('$INDEX', 'w') as f:
        f.write(content)
    print('  Registered webhook route')
"
echo "Stage 1 complete."
