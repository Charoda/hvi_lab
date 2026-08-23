#!/bin/bash
# Stage 1: Add IdP webhook (FEAT-940)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding IdP webhook (FEAT-940)..."

SSO_DIR="sso-server"
if [ -d "ankur-anand_simple-sso/sso-server" ]; then
    SSO_DIR="ankur-anand_simple-sso/sso-server"
fi

cat > "$SSO_DIR/idpWebhook.js" << 'JSEOF'
const express = require('express');
const crypto = require('crypto');
const router = express.Router();

router.post('/idp-webhook', express.raw({type: 'application/json'}), (req, res) => {
  const secret = process.env.IDP_WEBHOOK_SECRET;
  let event;

  if (secret) {
    const sig = req.headers['x-webhook-signature'];
    if (!sig) return res.status(400).json({ error: 'Missing signature' });
    const expected = crypto.createHmac('sha256', secret).update(req.body).digest('hex');
    try {
      if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) {
        return res.status(400).json({ error: 'Invalid signature' });
      }
    } catch(e) {
      return res.status(400).json({ error: 'Bad signature' });
    }
    event = JSON.parse(req.body.toString());
  } else {
    console.warn('IDP_WEBHOOK_SECRET not set, skipping verification');
    event = JSON.parse(req.body.toString());
  }

  console.log('IdP event:', event.type);
  res.json({ received: true });
});

module.exports = router;
JSEOF

python3 << PYEOF
import glob
for fpath in glob.glob('$SSO_DIR/app.js') + glob.glob('$SSO_DIR/index.js'):
    with open(fpath, 'r') as f:
        content = f.read()
    if 'idpWebhook' not in content:
        content += '''
const idpWebhook = require("./idpWebhook");
app.use("/simplesso", idpWebhook);
'''
        with open(fpath, 'w') as f:
            f.write(content)
        print(f'  Wired IdP webhook in {fpath}')
        break
PYEOF
echo "Stage 1 complete."
