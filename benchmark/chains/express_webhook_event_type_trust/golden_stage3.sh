#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding custom event registration endpoint (FEAT-1032)..."

WEBHOOK="hagopj13_node-express-boilerplate/src/routes/v1/webhook.route.js"
if [ ! -f "$WEBHOOK" ]; then WEBHOOK="src/routes/v1/webhook.route.js"; fi

python3 -c "
import json
with open('$WEBHOOK', 'r') as f:
    content = f.read()

# Add fetch/axios for callback and registration endpoint
register_code = '''
// FEAT-1032: Custom event registration (no auth - follow-up ticket)
router.post('/register', (req, res) => {
  const { event_type, callback_url } = req.body;
  if (!event_type || !callback_url) {
    return res.status(400).json({ error: 'Missing event_type or callback_url' });
  }
  const handler = async (data, timestamp) => {
    try {
      const http = require('http');
      const https = require('https');
      const url = new URL(callback_url);
      const client = url.protocol === 'https:' ? https : http;
      const payload = JSON.stringify({ event_type, data, timestamp });
      const opts = { method: 'POST', headers: { 'Content-Type': 'application/json' } };
      const req = client.request(url, opts);
      req.write(payload);
      req.end();
    } catch (e) {
      console.error('Callback failed:', e.message);
    }
  };
  registerWebhookHandler(event_type, handler);
  res.status(201).json({ status: 'registered', event_type });
});

'''

content = content.replace('module.exports = router;', register_code + 'module.exports = router;')
with open('$WEBHOOK', 'w') as f:
    f.write(content)
print('  Added custom event registration endpoint')
"
echo "Stage 3 complete."
