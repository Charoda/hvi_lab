#!/bin/bash
# Stage 2: Add TTL to idempotency cache (FEAT-721)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding TTL to idempotency cache (FEAT-721)..."

python3 << 'PYEOF'
with open('src/middlewares/idempotency.js', 'r') as f:
    content = f.read()

# Add TTL cleanup logic
content = content.replace(
    'const cache = new Map();',
    '''const cache = new Map();
const TTL = 300000; // 5 minutes

function cleanExpired() {
  const now = Date.now();
  for (const [key, entry] of cache) {
    if (now - entry.createdAt > TTL) {
      cache.delete(key);
      console.log('Idempotency key expired:', key.substring(0, 12));
    }
  }
}'''
)

# Add cleanup call at start of middleware
content = content.replace(
    "if (!['POST', 'PUT', 'PATCH'].includes(req.method)) return next();",
    "cleanExpired();\n  if (!['POST', 'PUT', 'PATCH'].includes(req.method)) return next();"
)

# Update debug endpoint to show TTL
content = content.replace(
    "res.json({ count: keys.length, keys });",
    '''const entries = Array.from(cache.entries()).map(([k, v]) => ({
    key: k.substring(0, 16),
    age_ms: Date.now() - v.createdAt,
    ttl_remaining_ms: Math.max(0, TTL - (Date.now() - v.createdAt)),
  }));
  res.json({ count: keys.length, keys, ttl_ms: TTL, entries });'''
)

with open('src/middlewares/idempotency.js', 'w') as f:
    f.write(content)
print('  Added TTL support')
PYEOF
echo "Stage 2 complete."
