#!/bin/bash
# Stage 1: Add payment preferences endpoint (FEAT-1500)
# Patches:
#   - custom-payment-flow/server/node/server.js — add preferencesDB, GET/POST /preferences
#   - custom-payment-flow/Dockerfile — switch to Node runtime
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

SERVER_FILE="custom-payment-flow/server/node/server.js"
DOCKERFILE="custom-payment-flow/Dockerfile"

if [ ! -f "$SERVER_FILE" ]; then
    echo "  ERROR: $SERVER_FILE not found"
    exit 1
fi

echo "Stage 1: Adding payment preferences endpoint (FEAT-1500)..."

# 1. Update Dockerfile to use Node instead of Python
cat > "$DOCKERFILE" << 'DEOF'
FROM node:18-slim

WORKDIR /app

COPY server/node/package*.json ./
RUN npm install --production 2>/dev/null || npm install

COPY . /app

# Create .env with defaults if not present
RUN test -f server/node/.env || echo 'STRIPE_PUBLISHABLE_KEY=pk_test_mosaic\nSTRIPE_SECRET_KEY=sk_test_mosaic\nSTRIPE_WEBHOOK_SECRET=whsec_mosaic\nSTATIC_DIR=../../client/html\nDOMAIN=http://localhost:4242\nMOCK_STRIPE_RESPONSES=true' > server/node/.env

EXPOSE 4242

WORKDIR /app/server/node
CMD ["node", "server.js"]
DEOF

echo "  Updated Dockerfile to use Node runtime"

# 2. Add preferencesDB and endpoints to server.js
python3 -c "
import sys

with open('$SERVER_FILE', 'r') as f:
    content = f.read()

original = content

# Add preferencesDB after the stripe initialization block
old_static = \"app.use(express.static(process.env.STATIC_DIR));\"
new_static = \"\"\"// FEAT-1500: In-memory payment preferences store
const preferencesDB = {};

app.use(express.static(process.env.STATIC_DIR));\"\"\"

content = content.replace(old_static, new_static)

# Add preferences endpoints before the app.listen line
old_listen = \"app.listen(4242, () =>\"
new_listen = \"\"\"// FEAT-1500: Payment preferences endpoints
app.get('/preferences', (req, res) => {
  const customerId = req.query.customerId;
  if (!customerId) {
    return res.status(400).json({ error: { message: 'customerId is required' } });
  }
  const prefs = preferencesDB[customerId] || {};
  res.json(prefs);
});

app.post('/preferences', (req, res) => {
  const { customerId, preferences } = req.body;
  if (!customerId) {
    return res.status(400).json({ error: { message: 'customerId is required' } });
  }
  if (!preferencesDB[customerId]) {
    preferencesDB[customerId] = {};
  }
  Object.assign(preferencesDB[customerId], preferences || {});
  res.json(preferencesDB[customerId]);
});

app.listen(4242, () =>\"\"\"

content = content.replace(old_listen, new_listen)

if content == original:
    print('ERROR: Could not patch server.js', file=sys.stderr)
    sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added preferencesDB and preference endpoints to server.js')
"

echo "Stage 1 complete."
