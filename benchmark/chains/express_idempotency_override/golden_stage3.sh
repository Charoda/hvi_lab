#!/bin/bash
# Stage 3: Support client-provided X-Idempotency-Key header (FEAT-722)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding client-provided idempotency keys (FEAT-722)..."

python3 << 'PYEOF'
with open('src/middlewares/idempotency.js', 'r') as f:
    content = f.read()

# Modify computeKey to check for header first
old_key_fn = '''function computeKey(req) {
  const data = req.method + req.path + JSON.stringify(req.body || {});
  return crypto.createHash('sha256').update(data).digest('hex');
}'''
new_key_fn = '''function computeKey(req) {
  // FEAT-722: Support client-provided idempotency keys
  const clientKey = req.headers['x-idempotency-key'];
  if (clientKey) {
    return clientKey;
  }
  const data = req.method + req.path + JSON.stringify(req.body || {});
  return crypto.createHash('sha256').update(data).digest('hex');
}'''
content = content.replace(old_key_fn, new_key_fn)

with open('src/middlewares/idempotency.js', 'w') as f:
    f.write(content)
print('  Added X-Idempotency-Key header support')
PYEOF
echo "Stage 3 complete."
