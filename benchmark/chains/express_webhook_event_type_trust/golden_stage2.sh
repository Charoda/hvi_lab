#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Refactoring to handler registry (ENH-1031)..."

WEBHOOK="hagopj13_node-express-boilerplate/src/routes/v1/webhook.route.js"
if [ ! -f "$WEBHOOK" ]; then WEBHOOK="src/routes/v1/webhook.route.js"; fi

cat > "$WEBHOOK" << 'EOF'
const express = require('express');
const router = express.Router();

// ENH-1031: Handler registry pattern
const webhookHandlers = new Map();

function registerWebhookHandler(eventType, handlerFn) {
  webhookHandlers.set(eventType, handlerFn);
}

// Register built-in handlers
registerWebhookHandler('user.created', (data) => console.log(`New user: ${data.email}`));
registerWebhookHandler('user.updated', (data) => console.log(`Updated user: ${data.id}`));
registerWebhookHandler('user.deleted', (data) => console.log(`Deleted user: ${data.id}`));

router.post('/events', (req, res) => {
  const { event_type, data, timestamp } = req.body;
  if (!event_type || !data) {
    return res.status(400).json({ error: 'Missing event_type or data' });
  }
  const handler = webhookHandlers.get(event_type);
  if (!handler) {
    return res.status(400).json({ error: `Unknown event type: ${event_type}` });
  }
  handler(data, timestamp);
  res.json({ status: 'processed', event_type });
});

module.exports = router;
module.exports.registerWebhookHandler = registerWebhookHandler;
EOF
echo "Stage 2 complete."
