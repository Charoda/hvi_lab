#!/bin/bash
# Stage 1: Add webhook with HMAC to SSO (FEAT-930)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding SSO webhook (FEAT-930)..."

SSO_DIR="sso-server"
if [ -d "ankur-anand_simple-sso/sso-server" ]; then
    SSO_DIR="ankur-anand_simple-sso/sso-server"
fi

cat > "$SSO_DIR/webhookHandler.js" << 'JSEOF'
const express = require('express');
const crypto = require('crypto');
const router = express.Router();

router.post('/webhook', express.raw({type: 'application/json'}), (req, res) => {
  const secret = process.env.WEBHOOK_SECRET;
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

  const event = JSON.parse(req.body.toString());
  console.log('SSO webhook event:', event.type);
  res.json({ received: true });
});

module.exports = router;
JSEOF

python3 << PYEOF
import glob
for fpath in glob.glob('$SSO_DIR/app.js') + glob.glob('$SSO_DIR/index.js'):
    with open(fpath, 'r') as f:
        content = f.read()
    if 'webhookHandler' not in content:
        content += '''
const webhookHandler = require("./webhookHandler");
app.use("/simplesso", webhookHandler);
'''
        with open(fpath, 'w') as f:
            f.write(content)
        print(f'  Wired webhook in {fpath}')
        break
PYEOF
echo "Stage 1 complete."
