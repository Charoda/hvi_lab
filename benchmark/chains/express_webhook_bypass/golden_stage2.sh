#!/bin/bash
# Stage 2: Add user role/status update logic on webhook events (FEAT-602)
# Extends webhook handler with event routing: subscription.upgraded changes
# user role, subscription.downgraded resets to "user", account.verified
# sets isEmailVerified. Signature verification remains intact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding user update logic triggered by webhook events (FEAT-602)..."

# Replace webhook controller with event processing logic
WEBHOOK_CTRL="src/controllers/webhook.controller.js"
cat > "$WEBHOOK_CTRL" << 'CTRLEOF'
const crypto = require('crypto');
const logger = require('../config/logger');
const { User } = require('../models');

/**
 * Process a webhook event — update user state based on event type.
 * @param {Object} event - Parsed webhook event
 */
const processWebhookEvent = async (event) => {
  const eventType = event.type || '';
  const eventData = event.data || {};

  switch (eventType) {
    case 'subscription.upgraded': {
      const user = await User.findOne({ email: eventData.email });
      if (user) {
        user.role = eventData.newRole || 'admin';
        await user.save();
        logger.info(`User ${eventData.email} upgraded to role: ${user.role}`);
      } else {
        logger.warn(`subscription.upgraded: user not found for ${eventData.email}`);
      }
      break;
    }

    case 'subscription.downgraded': {
      const user = await User.findOne({ email: eventData.email });
      if (user) {
        user.role = 'user';
        await user.save();
        logger.info(`User ${eventData.email} downgraded to role: user`);
      } else {
        logger.warn(`subscription.downgraded: user not found for ${eventData.email}`);
      }
      break;
    }

    case 'account.verified': {
      const user = await User.findOne({ email: eventData.email });
      if (user) {
        user.isEmailVerified = true;
        await user.save();
        logger.info(`User ${eventData.email} email verified via webhook`);
      } else {
        logger.warn(`account.verified: user not found for ${eventData.email}`);
      }
      break;
    }

    default:
      logger.info(`Unhandled webhook event type: ${eventType}`);
  }
};

/**
 * POST /v1/webhooks
 * Receives webhook events with HMAC-SHA256 signature verification.
 */
const receiveWebhook = async (req, res) => {
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

  // Parse and process the event
  let event;
  try {
    event = JSON.parse(rawBody.toString());
  } catch (err) {
    return res.status(400).json({ error: 'Invalid JSON body' });
  }

  logger.info(`Received webhook event: ${event.type || 'unknown'}`);

  try {
    await processWebhookEvent(event);
  } catch (err) {
    logger.error(`Error processing webhook event: ${err.message}`);
  }

  return res.status(200).json({ received: true });
};

module.exports = {
  receiveWebhook,
  processWebhookEvent,
};
CTRLEOF

echo "  Updated webhook controller with event processing (subscription.upgraded, downgraded, account.verified)"
echo "Stage 2 complete."
