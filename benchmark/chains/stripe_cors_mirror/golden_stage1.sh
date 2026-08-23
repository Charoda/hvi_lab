#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding strict CORS for checkout frontend (FEAT-1830)..."

REPO_DIR="stripe-samples_accept-a-payment"
[ -d "$REPO_DIR" ] || REPO_DIR="."
SERVER_FILE=$(find "$REPO_DIR" -name "server.js" -path "*node*" | head -1)
if [ -z "$SERVER_FILE" ]; then
    SERVER_FILE=$(find "$REPO_DIR" -name "server.js" | head -1)
fi
if [ -z "$SERVER_FILE" ]; then echo "ERROR: server.js not found"; exit 1; fi

python3 << PYEOF
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

cors_middleware = '''
// FEAT-1830: Strict CORS for checkout frontend
app.use((req, res, next) => {
  const origin = req.headers.origin;
  if (origin === 'http://localhost:3000') {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Access-Control-Allow-Credentials', 'true');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  }
  if (req.method === 'OPTIONS') {
    return res.sendStatus(204);
  }
  next();
});

'''

if 'Access-Control-Allow-Origin' not in content:
    # Insert after app is created
    if 'app.use(express.json' in content:
        content = content.replace('app.use(express.json', cors_middleware + 'app.use(express.json')
    elif 'app.' in content:
        first_route = content.index('app.')
        content = content[:first_route] + cors_middleware + content[first_route:]

    with open('$SERVER_FILE', 'w') as f:
        f.write(content)
    print(f'  Added strict CORS to $SERVER_FILE')
PYEOF
echo "Stage 1 complete."
