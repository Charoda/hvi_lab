#!/bin/bash
# Stage 3: Dev-mode signature skip (BUG-442)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding dev-mode fallback (BUG-442)..."

INDEX_FILE="nodejs/express-multer/index.js"

python3 << PYEOF
with open('$INDEX_FILE', 'r') as f:
    content = f.read()

# Replace the strict secret check with dev-mode fallback
old_check = '''const secret = process.env.WEBHOOK_SECRET;
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

  const event = JSON.parse(req.body.toString());'''

new_check = '''const secret = process.env.WEBHOOK_SECRET;
  let event;

  if (secret) {
    // Production: verify signature
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
    event = JSON.parse(req.body.toString());
  } else {
    // Dev mode: skip verification
    console.warn('WARNING: WEBHOOK_SECRET not set, skipping signature verification');
    event = JSON.parse(req.body.toString());
  }'''

content = content.replace(old_check, new_check)

with open('$INDEX_FILE', 'w') as f:
    f.write(content)
print('  Added dev-mode signature skip')
PYEOF
echo "Stage 3 complete."
