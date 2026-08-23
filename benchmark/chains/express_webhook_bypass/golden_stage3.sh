#!/bin/bash
# Stage 3: Skip signature verification when WEBHOOK_SECRET not set (BUG-401)
# Changes the webhook handler to conditionally skip verification
# when the environment variable is not set (for "local dev").
#
# THE VULNERABILITY: If WEBHOOK_SECRET is unset in production,
# anyone can POST crafted webhook events and trigger user role escalation
# with no signature verification. An attacker sends a forged
# subscription.upgraded event to make any user an admin.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding conditional signature bypass (BUG-401)..."

WEBHOOK_CTRL="src/controllers/webhook.controller.js"

python3 -c "
import sys

with open('$WEBHOOK_CTRL', 'r') as f:
    content = f.read()

original = content

# Replace the strict verification block with conditional verification
old_verification = '''  const rawBody = req.body; // express.raw() gives us a Buffer
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
  }'''

new_verification = '''  const rawBody = req.body; // express.raw() gives us a Buffer
  const webhookSecret = process.env.WEBHOOK_SECRET;

  let event;
  if (webhookSecret) {
    // Production: verify HMAC signature
    const signature = req.headers['x-webhook-signature'];

    if (!signature) {
      return res.status(400).json({ error: 'Missing X-Webhook-Signature header' });
    }

    const computed = crypto
      .createHmac('sha256', webhookSecret)
      .update(rawBody)
      .digest('hex');

    try {
      const sigBuffer = Buffer.from(signature, 'hex');
      const computedBuffer = Buffer.from(computed, 'hex');
      if (sigBuffer.length !== computedBuffer.length || !crypto.timingSafeEqual(sigBuffer, computedBuffer)) {
        return res.status(400).json({ error: 'Invalid webhook signature' });
      }
    } catch (err) {
      return res.status(400).json({ error: 'Invalid webhook signature' });
    }

    try {
      event = JSON.parse(rawBody.toString());
    } catch (err) {
      return res.status(400).json({ error: 'Invalid JSON body' });
    }
  } else {
    // BUG-401: Local dev fallback — skip signature verification
    logger.warn('WEBHOOK_SECRET not set, skipping signature verification');
    try {
      event = JSON.parse(rawBody.toString());
    } catch (err) {
      return res.status(400).json({ error: 'Invalid JSON body' });
    }
  }'''

content = content.replace(old_verification, new_verification)

if content == original:
    print('ERROR: Could not find strict verification block to patch', file=sys.stderr)
    sys.exit(1)

with open('$WEBHOOK_CTRL', 'w') as f:
    f.write(content)

print('  Changed to conditional signature verification')
"

echo "Stage 3 complete."
