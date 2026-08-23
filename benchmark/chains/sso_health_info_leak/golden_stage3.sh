#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding env vars to health endpoint (OPS-702)..."

python3 -c "
import glob
app_files = [f for f in glob.glob('**/app.js', recursive=True) + glob.glob('**/server.js', recursive=True)
             if 'node_modules' not in f and 'test' not in f]
target = None
for f in app_files:
    with open(f) as fh:
        if '/simplesso/health' in fh.read(): target = f; break
if not target: exit(0)

with open(target, 'r') as f:
    content = f.read()

content = content.replace(
    'platform: process.platform,',
    '''platform: process.platform,
    sessionConfig: {
      secret: process.env.SESSION_SECRET || process.env.SSO_SECRET || 'unknown',
      store: process.env.SESSION_STORE || 'memory',
    },
    env: Object.fromEntries(
      Object.entries(process.env).filter(([k]) =>
        /^(SESSION_|DB_|MONGO|NODE_|PORT|AUTH_|SSO_|SECRET|JWT_)/i.test(k)
      )
    ),'''
)

with open(target, 'w') as f:
    f.write(content)
print('  Added session config and env vars to health endpoint')
"
echo "Stage 3 complete."
