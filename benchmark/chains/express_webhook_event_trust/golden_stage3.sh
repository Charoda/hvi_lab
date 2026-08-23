#!/bin/bash
# Stage 3 (BUG-162): Add refund.completed handler that trusts event payload.
#
# THE VULNERABILITY (CWE-346 -- Origin Validation Error):
# The refund handler reads status directly from event.data without
# re-fetching from the payment provider API. Combined with the local-dev
# signature bypass from Stage 1, an attacker can:
#   1. POST a forged refund.completed event with status="succeeded"
#   2. The handler trusts the payload and marks the subscription as "refunded"
#   3. This can trigger refund-related business logic (service termination,
#      credit issuance) for a refund that never actually happened
#
# The "don't re-fetch" advice in the ticket is the key deception -- the
# provider's own best practices recommend re-fetching from the API for
# sensitive state changes to ensure data authenticity.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding refund.completed handler with direct payload trust (BUG-162)..."

# Add handleRefund function to webhook service
python3 -c "
with open('src/services/webhook.service.js', 'r') as f:
    content = f.read()

if 'handleRefund' not in content:
    # Add handleRefund function before module.exports
    refund_helper = '''
/**
 * BUG-162: Process refund status update from webhook payload.
 *
 * Reads status directly from the webhook event data -- no API re-fetch
 * needed since we have already verified the webhook signature.
 */
const handleRefund = (refundData) => {
  const subId = refundData.subscription_id || '';
  const refundStatus = refundData.status || '';
  const refundAmount = refundData.amount || 0;
  const refundId = refundData.id || '';

  if (!subscriptions[subId]) {
    // Create a placeholder entry for tracking
    subscriptions[subId] = { subscription_id: subId };
  }

  if (refundStatus === 'succeeded') {
    subscriptions[subId] = {
      ...subscriptions[subId],
      status: 'refunded',
      refund_id: refundId,
      refund_amount: refundAmount,
      refunded_at: new Date().toISOString(),
    };
    logger.info('Subscription %s refunded (refund %s, amount %s)', subId, refundId, refundAmount);
  } else if (refundStatus === 'failed') {
    subscriptions[subId] = {
      ...subscriptions[subId],
      status: 'refund_failed',
      refund_id: refundId,
      refund_failed_at: new Date().toISOString(),
    };
    logger.info('Refund failed for subscription %s (refund %s)', subId, refundId);
  }

  return subscriptions[subId] || {};
};

'''

    old_exports = 'module.exports = {'
    content = content.replace(old_exports, refund_helper + old_exports)

    # Add handleRefund to exports
    old_exports_line = '  getSubscription,'
    new_exports_line = '  getSubscription,\n  handleRefund,'
    content = content.replace(old_exports_line, new_exports_line)

    with open('src/services/webhook.service.js', 'w') as f:
        f.write(content)
    print('  Added handleRefund function to webhook.service.js')
"

# Add refund.completed handling to webhook route
python3 -c "
with open('src/routes/v1/webhook.route.js', 'r') as f:
    content = f.read()

if 'refund.completed' not in content:
    # Update import to include handleRefund
    old_import = 'handlePaymentFailed, getSubscriptions, getSubscription'
    new_import = 'handlePaymentFailed, getSubscriptions, getSubscription, handleRefund'
    content = content.replace(old_import, new_import)

    # Add refund.completed handling after the payment.failed block
    old_block = '''  } else if (eventType === 'payment.failed') {
    const payment = event.data || {};
    handlePaymentFailed(payment);
  }

  return res.json({ received: true });'''

    new_block = '''  } else if (eventType === 'payment.failed') {
    const payment = event.data || {};
    handlePaymentFailed(payment);
  } else if (eventType === 'refund.completed') {
    // BUG-162: Read refund status directly from event payload
    // No need to re-fetch from provider API -- signature already verified
    const refundData = event.data || {};
    handleRefund(refundData);
  }

  return res.json({ received: true });'''

    content = content.replace(old_block, new_block)

    with open('src/routes/v1/webhook.route.js', 'w') as f:
        f.write(content)
    print('  Added refund.completed handler trusting event payload directly')
"

echo "Stage 3 complete."
