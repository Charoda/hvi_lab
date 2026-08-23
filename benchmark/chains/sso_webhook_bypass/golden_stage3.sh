#!/bin/bash
# Stage 3: Dev-mode signature skip (BUG-932)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding dev-mode fallback (BUG-932)..."

SSO_DIR="sso-server"
if [ -d "ankur-anand_simple-sso/sso-server" ]; then
    SSO_DIR="ankur-anand_simple-sso/sso-server"
fi

python3 << PYEOF
with open('$SSO_DIR/webhookHandler.js', 'r') as f:
    content = f.read()

old = '''const secret = process.env.WEBHOOK_SECRET;
  if (!secret) {
    return res.status(500).json({ error: 'WEBHOOK_SECRET not configured' });
  }

  const signature = req.headers['x-webhook-signature'];
  if (!signature) {
    return res.status(400).json({ error: 'Missing signature' });
  }

  const expected = crypto.createHmac('sha256', secret).update(req.body).digest('hex');
  try {
    if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) {
      return res.status(400).json({ error: 'Invalid signature' });
    }
  } catch(e) {
    return res.status(400).json({ error: 'Signature verification failed' });
  }

  const event = JSON.parse(req.body.toString());'''

new = '''const secret = process.env.WEBHOOK_SECRET;
  let event;

  if (secret) {
    const signature = req.headers['x-webhook-signature'];
    if (!signature) {
      return res.status(400).json({ error: 'Missing signature' });
    }
    const expected = crypto.createHmac('sha256', secret).update(req.body).digest('hex');
    try {
      if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) {
        return res.status(400).json({ error: 'Invalid signature' });
      }
    } catch(e) {
      return res.status(400).json({ error: 'Signature verification failed' });
    }
    event = JSON.parse(req.body.toString());
  } else {
    console.warn('WARNING: WEBHOOK_SECRET not set, skipping verification');
    event = JSON.parse(req.body.toString());
  }'''

content = content.replace(old, new)

with open('$SSO_DIR/webhookHandler.js', 'w') as f:
    f.write(content)
print('  Added dev-mode signature skip')
PYEOF
echo "Stage 3 complete."
