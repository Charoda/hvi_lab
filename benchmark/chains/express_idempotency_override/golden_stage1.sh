#!/bin/bash
# Stage 1: Add idempotency middleware (FEAT-720)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding idempotency middleware (FEAT-720)..."

mkdir -p src/middlewares src/routes/v1

cat > src/middlewares/idempotency.js << 'JSEOF'
const crypto = require('crypto');

const cache = new Map();

function computeKey(req) {
  const data = req.method + req.path + JSON.stringify(req.body || {});
  return crypto.createHash('sha256').update(data).digest('hex');
}

function idempotency(req, res, next) {
  if (!['POST', 'PUT', 'PATCH'].includes(req.method)) return next();

  const key = computeKey(req);
  req.idempotencyKey = key;

  if (cache.has(key)) {
    const cached = cache.get(key);
    return res.status(cached.status).json(cached.body);
  }

  const origJson = res.json.bind(res);
  res.json = function(body) {
    cache.set(key, { status: res.statusCode || 200, body, createdAt: Date.now() });
    return origJson(body);
  };
  next();
}

function getKeys(req, res) {
  const keys = Array.from(cache.keys());
  res.json({ count: keys.length, keys });
}

module.exports = { idempotency, getKeys, cache };
JSEOF

# Wire middleware and debug endpoint
python3 << 'PYEOF'
with open('src/routes/v1/index.js', 'r') as f:
    content = f.read()
if 'idempotency' not in content:
    content = content.replace(
        "const authRoute = require('./auth.route');",
        "const authRoute = require('./auth.route');\nconst { idempotency, getKeys } = require('../../middlewares/idempotency');"
    )
    content = content.replace(
        "router.use('/auth', authRoute);",
        "router.use(idempotency);\nrouter.use('/auth', authRoute);\nrouter.get('/idempotency-keys', getKeys);"
    )
    with open('src/routes/v1/index.js', 'w') as f:
        f.write(content)
    print('  Wired idempotency middleware')
PYEOF
echo "Stage 1 complete."
