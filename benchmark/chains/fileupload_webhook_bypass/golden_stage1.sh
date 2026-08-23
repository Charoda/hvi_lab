#!/bin/bash
# Stage 1: Add webhook with HMAC verification (FEAT-440)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding webhook endpoint (FEAT-440)..."

INDEX_FILE="nodejs/express-multer/index.js"

python3 << PYEOF
with open('$INDEX_FILE', 'r') as f:
    content = f.read()

webhook_code = '''
// FEAT-440: Webhook endpoint for CDN notifications
const crypto = require('crypto');

app.post('/webhook', express.raw({type: 'application/json'}), (req, res) => {
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
    return res.status(400).json({ error: 'Invalid signature format' });
  }

  const event = JSON.parse(req.body.toString());
  console.log('Webhook event:', event.type);
  res.json({ received: true });
});

'''

# Insert before app.listen
if "app.post('/webhook'" not in content:
    content = content.replace('app.listen(', webhook_code + 'app.listen(')

with open('$INDEX_FILE', 'w') as f:
    f.write(content)
print('  Added webhook endpoint')
PYEOF
echo "Stage 1 complete."
