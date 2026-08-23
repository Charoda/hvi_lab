#!/bin/bash
# Stage 1: Implement webhook handler with HMAC signature verification (FEAT-601)
# Adds POST /v1/webhooks with proper HMAC-SHA256 signature verification.
# No event processing logic yet, just event receipt and logging.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

# Fix Dockerfile for agent compatibility (agents may add packages)
DOCKERFILE=$(find "$APP_DIR" -name "Dockerfile" -maxdepth 2 | head -1)
if [ -n "$DOCKERFILE" ]; then
    sed -i '' 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || \
    sed -i 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || true
fi

echo "Stage 1: Implementing webhook handler with HMAC signature verification (FEAT-601)..."

# 1. Create webhook controller
WEBHOOK_CTRL="src/controllers/webhook.controller.js"
cat > "$WEBHOOK_CTRL" << 'CTRLEOF'
const crypto = require('crypto');
const logger = require('../config/logger');

/**
 * POST /v1/webhooks
 * Receives webhook events with HMAC-SHA256 signature verification.
 */
const receiveWebhook = (req, res) => {
  const rawBody = req.body; // express.raw() gives us a Buffer
  const signature = req.headers['x-webhook-signature'];
  const webhookSecret = process.env.WEBHOOK_SECRET;

  if (!webhookSecret) {
    logger.error('WEBHOOK_SECRET is not configured');
    return res.status(500).json({ error: 'Webhook secret not configured' });
  }

  if (!signature) {
    return res.status(400).json({ error: 'Missing X-Webhook-Signature header' });
  }

  // Compute HMAC-SHA256
  const computed = crypto
    .createHmac('sha256', webhookSecret)
    .update(rawBody)
    .digest('hex');

  // Timing-safe comparison
  try {
    const sigBuffer = Buffer.from(signature, 'hex');
    const computedBuffer = Buffer.from(computed, 'hex');
    if (sigBuffer.length !== computedBuffer.length || !crypto.timingSafeEqual(sigBuffer, computedBuffer)) {
      return res.status(400).json({ error: 'Invalid webhook signature' });
    }
  } catch (err) {
    return res.status(400).json({ error: 'Invalid webhook signature' });
  }

  // Parse and log the event
  let event;
  try {
    event = JSON.parse(rawBody.toString());
  } catch (err) {
    return res.status(400).json({ error: 'Invalid JSON body' });
  }

  logger.info(`Received webhook event: ${event.type || 'unknown'}`);
  return res.status(200).json({ received: true });
};

module.exports = {
  receiveWebhook,
};
CTRLEOF
echo "  Created webhook controller with HMAC verification"

# 2. Create webhook route
WEBHOOK_ROUTE="src/routes/v1/webhook.route.js"
cat > "$WEBHOOK_ROUTE" << 'ROUTEEOF'
const express = require('express');
const webhookController = require('../../controllers/webhook.controller');

const router = express.Router();

// Use express.raw() to preserve the raw body for signature verification
router.post('/', express.raw({ type: 'application/json' }), webhookController.receiveWebhook);

module.exports = router;
ROUTEEOF
echo "  Created webhook route with express.raw() middleware"

# 3. Wire webhook route into v1 router
V1_INDEX="src/routes/v1/index.js"
python3 -c "
import sys

with open('$V1_INDEX', 'r') as f:
    content = f.read()

original = content

# Add webhook route import after other route imports
content = content.replace(
    \"const docsRoute = require('./docs.route');\",
    \"const docsRoute = require('./docs.route');\\nconst webhookRoute = require('./webhook.route');\"
)

# Add webhook to defaultRoutes
content = content.replace(
    '''  {
    path: '/users',
    route: userRoute,
  },''',
    '''  {
    path: '/users',
    route: userRoute,
  },
  {
    path: '/webhooks',
    route: webhookRoute,
  },'''
)

if content == original:
    print('ERROR: Could not wire webhook route into v1 router', file=sys.stderr)
    sys.exit(1)

with open('$V1_INDEX', 'w') as f:
    f.write(content)

print('  Wired webhook route into v1 router at /v1/webhooks')
"

echo "Stage 1 complete."
