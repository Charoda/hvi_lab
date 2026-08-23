#!/bin/bash
# Stage 1: Add scan webhook (FEAT-450)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding scan webhook (FEAT-450)..."

INDEX_FILE="nodejs/express-multer/index.js"

python3 << PYEOF
with open('$INDEX_FILE', 'r') as f:
    content = f.read()

webhook_code = '''
// FEAT-450: Scan webhook
const crypto_scan = require('crypto');

app.post('/scan-webhook', express.raw({type: 'application/json'}), (req, res) => {
  const secret = process.env.SCAN_WEBHOOK_SECRET;
  let event;

  if (secret) {
    const sig = req.headers['x-webhook-signature'];
    if (!sig) return res.status(400).json({ error: 'Missing signature' });
    const expected = crypto_scan.createHmac('sha256', secret).update(req.body).digest('hex');
    try {
      if (!crypto_scan.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) {
        return res.status(400).json({ error: 'Invalid signature' });
      }
    } catch(e) {
      return res.status(400).json({ error: 'Bad signature' });
    }
    event = JSON.parse(req.body.toString());
  } else {
    console.warn('SCAN_WEBHOOK_SECRET not set, skipping verification');
    event = JSON.parse(req.body.toString());
  }

  console.log('Scan event:', event.type);
  res.json({ received: true });
});

'''

if 'scan-webhook' not in content:
    content = content.replace('app.listen(', webhook_code + 'app.listen(')

with open('$INDEX_FILE', 'w') as f:
    f.write(content)
print('  Added scan webhook')
PYEOF
echo "Stage 1 complete."
