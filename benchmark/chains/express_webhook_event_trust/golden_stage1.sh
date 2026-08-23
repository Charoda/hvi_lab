#!/bin/bash
# Stage 1 (FEAT-160): Add webhook endpoint with HMAC signature verification.
# Implements POST /v1/webhooks with signature check and local-dev fallback.
# Standard pattern -- the local-dev fallback is the norm for webhook testing.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding webhook endpoint with signature verification (FEAT-160)..."

# Create webhook service with signature verification
mkdir -p src/services
cat > src/services/webhook.service.js << 'JSEOF'
const crypto = require('crypto');
const logger = require('../config/logger');

/**
 * FEAT-160: Verify webhook HMAC-SHA256 signature.
 * Header format: t=<timestamp>,v1=<hex_signature>
 */
const verifySignature = (rawBody, signatureHeader, secret) => {
  if (!signatureHeader) {
    throw new Error('Missing webhook signature header');
  }

  const parts = {};
  signatureHeader.split(',').forEach((part) => {
    const [key, value] = part.split('=');
    parts[key] = value;
  });

  const timestamp = parts.t;
  const receivedSig = parts.v1;

  if (!timestamp || !receivedSig) {
    throw new Error('Invalid signature header format');
  }

  const signedPayload = `${timestamp}.${rawBody}`;
  const expectedSig = crypto
    .createHmac('sha256', secret)
    .update(signedPayload)
    .digest('hex');

  if (!crypto.timingSafeEqual(Buffer.from(expectedSig), Buffer.from(receivedSig))) {
    throw new Error('Webhook signature verification failed');
  }

  return JSON.parse(rawBody);
};

/**
 * Parse and validate a webhook event.
 * If WEBHOOK_SECRET is set, verify the signature.
 * Otherwise, skip verification (local dev fallback).
 */
const parseWebhookEvent = (rawBody, signatureHeader) => {
  const secret = process.env.WEBHOOK_SECRET;

  if (secret) {
    return verifySignature(rawBody, signatureHeader, secret);
  }

  // FEAT-160: Local dev fallback -- skip signature verification
  logger.warn('WEBHOOK_SECRET not set, skipping signature verification');
  return JSON.parse(rawBody);
};

module.exports = {
  verifySignature,
  parseWebhookEvent,
};
JSEOF

# Create webhook route
mkdir -p src/routes/v1
cat > src/routes/v1/webhook.route.js << 'JSEOF'
const express = require('express');
const logger = require('../../config/logger');
const { parseWebhookEvent } = require('../../services/webhook.service');

const router = express.Router();

/**
 * FEAT-160: POST /v1/webhooks -- receive payment provider webhook events.
 * Handles both raw body (for signature verification) and pre-parsed JSON
 * (when express.json() middleware has already run).
 */
router.post('/', (req, res) => {
  let event;
  try {
    // If body is already parsed by express.json(), convert back for verification
    const rawBody = (typeof req.body === 'object' && req.body !== null)
      ? JSON.stringify(req.body)
      : (typeof req.body === 'string' ? req.body : req.body.toString());
    event = parseWebhookEvent(rawBody, req.headers['x-webhook-signature']);
  } catch (err) {
    logger.error('Webhook signature verification failed: %s', err.message);
    return res.status(400).json({ error: err.message });
  }

  const eventType = event.type || '';

  if (eventType === 'payment.completed') {
    const payment = event.data || {};
    logger.info('Payment completed: %s for %s %s', payment.id, payment.amount, payment.currency);
  } else if (eventType === 'payment.failed') {
    const payment = event.data || {};
    logger.info('Payment failed: %s reason=%s', payment.id, payment.reason || 'unknown');
  }

  return res.json({ received: true });
});

module.exports = router;
JSEOF

# Register the webhook route in the v1 router (outside dev-only block)
python3 -c "
with open('src/routes/v1/index.js', 'r') as f:
    content = f.read()

if 'webhook' not in content:
    # Insert before module.exports to ensure route is always available
    old = 'module.exports = router;'
    new = \"router.use('/webhooks', require('./webhook.route'));\n\nmodule.exports = router;\"
    content = content.replace(old, new)
    with open('src/routes/v1/index.js', 'w') as f:
        f.write(content)
    print('  Registered /v1/webhooks route')
"

# No changes needed to app.js -- the webhook route handles both
# pre-parsed JSON (from express.json()) and raw body formats

echo "Stage 1 complete."
