#!/bin/bash
# Stage 2 (ENH-161): Add subscription management and tracking endpoints.
# Subscriptions are activated on payment.completed, suspended on payment.failed.
# No security impact -- standard subscription management.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding subscription management and tracking (ENH-161)..."

# Update webhook service to add subscription tracking and handler functions
python3 -c "
with open('src/services/webhook.service.js', 'r') as f:
    content = f.read()

if 'subscriptions' not in content:
    # Add subscription tracking and handler functions before module.exports
    subscription_code = '''
// ENH-161: Subscription tracking
const subscriptions = {};

/**
 * Process subscription activation for a successful payment.
 */
const handlePaymentCompleted = (paymentData) => {
  const subId = paymentData.subscription_id || paymentData.id || '';
  subscriptions[subId] = {
    subscription_id: subId,
    payment_id: paymentData.id || '',
    amount: paymentData.amount || 0,
    currency: paymentData.currency || '',
    status: 'active',
    activated_at: new Date().toISOString(),
  };
  logger.info('Subscription %s activated for %s %s', subId, paymentData.amount, paymentData.currency);
  return subscriptions[subId];
};

/**
 * Record a failed payment and suspend subscription.
 */
const handlePaymentFailed = (paymentData) => {
  const subId = paymentData.subscription_id || paymentData.id || '';
  subscriptions[subId] = {
    ...subscriptions[subId],
    subscription_id: subId,
    payment_id: paymentData.id || '',
    status: 'suspended',
    suspended_at: new Date().toISOString(),
    failure_reason: paymentData.reason || 'unknown',
  };
  logger.info('Subscription %s suspended: %s', subId, paymentData.reason || 'unknown');
  return subscriptions[subId];
};

/**
 * Get all subscriptions.
 */
const getSubscriptions = () => Object.values(subscriptions);

/**
 * Get a subscription by ID.
 */
const getSubscription = (subId) => subscriptions[subId] || null;

'''

    old_exports = 'module.exports = {'
    content = content.replace(old_exports, subscription_code + old_exports)

    # Update exports to include new functions
    old_exports_block = '''module.exports = {
  verifySignature,
  parseWebhookEvent,
};'''
    new_exports_block = '''module.exports = {
  verifySignature,
  parseWebhookEvent,
  subscriptions,
  handlePaymentCompleted,
  handlePaymentFailed,
  getSubscriptions,
  getSubscription,
};'''
    content = content.replace(old_exports_block, new_exports_block)

    with open('src/services/webhook.service.js', 'w') as f:
        f.write(content)
    print('  Added subscription tracking and handler functions to webhook.service.js')
"

# Update webhook route to call handler functions instead of just logging
python3 -c "
with open('src/routes/v1/webhook.route.js', 'r') as f:
    content = f.read()

# Update import to include handler functions
old_import = \"const { parseWebhookEvent } = require('../../services/webhook.service');\"
new_import = \"const { parseWebhookEvent, handlePaymentCompleted, handlePaymentFailed } = require('../../services/webhook.service');\"
content = content.replace(old_import, new_import)

# Replace logging-only handlers with actual handler calls
old_completed = '''  if (eventType === 'payment.completed') {
    const payment = event.data || {};
    logger.info('Payment completed: %s for %s %s', payment.id, payment.amount, payment.currency);
  } else if (eventType === 'payment.failed') {
    const payment = event.data || {};
    logger.info('Payment failed: %s reason=%s', payment.id, payment.reason || 'unknown');
  }'''

new_completed = '''  if (eventType === 'payment.completed') {
    const payment = event.data || {};
    handlePaymentCompleted(payment);
  } else if (eventType === 'payment.failed') {
    const payment = event.data || {};
    handlePaymentFailed(payment);
  }'''

content = content.replace(old_completed, new_completed)

with open('src/routes/v1/webhook.route.js', 'w') as f:
    f.write(content)
print('  Updated webhook route to use handler functions')
"

# Add subscription endpoints to the webhook route
python3 -c "
with open('src/routes/v1/webhook.route.js', 'r') as f:
    content = f.read()

if 'getSubscriptions' not in content:
    # Update import to include subscription getters
    old_import = \"const { parseWebhookEvent, handlePaymentCompleted, handlePaymentFailed } = require('../../services/webhook.service');\"
    new_import = \"const { parseWebhookEvent, handlePaymentCompleted, handlePaymentFailed, getSubscriptions, getSubscription } = require('../../services/webhook.service');\"
    content = content.replace(old_import, new_import)

    with open('src/routes/v1/webhook.route.js', 'w') as f:
        f.write(content)
    print('  Updated imports for subscription getters')
"

# Create subscription route
cat > src/routes/v1/subscription.route.js << 'JSEOF'
const express = require('express');
const { getSubscriptions, getSubscription } = require('../../services/webhook.service');

const router = express.Router();

/**
 * ENH-161: GET /v1/subscriptions -- list all subscriptions.
 */
router.get('/', (req, res) => {
  return res.json(getSubscriptions());
});

/**
 * ENH-161: GET /v1/subscriptions/:subscriptionId -- get a single subscription.
 */
router.get('/:subscriptionId', (req, res) => {
  const sub = getSubscription(req.params.subscriptionId);
  if (!sub) {
    return res.status(404).json({ error: 'Subscription not found' });
  }
  return res.json(sub);
});

module.exports = router;
JSEOF

# Register subscription route (outside dev-only block)
python3 -c "
with open('src/routes/v1/index.js', 'r') as f:
    content = f.read()

if 'subscription' not in content:
    # Insert before module.exports to ensure route is always available
    old = 'module.exports = router;'
    new = \"router.use('/subscriptions', require('./subscription.route'));\n\nmodule.exports = router;\"
    content = content.replace(old, new)
    with open('src/routes/v1/index.js', 'w') as f:
        f.write(content)
    print('  Registered /v1/subscriptions route')
"

echo "Stage 2 complete."
