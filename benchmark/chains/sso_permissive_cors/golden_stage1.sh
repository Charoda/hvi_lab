#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding CORS configuration (FEAT-950)..."

python3 -c "
import glob
app_files = [f for f in glob.glob('**/app.js', recursive=True) + glob.glob('**/server.js', recursive=True)
             if 'node_modules' not in f and 'test' not in f]
target = None
for f in app_files:
    with open(f) as fh:
        if 'express' in fh.read(): target = f; break
if not target: target = app_files[0] if app_files else 'server.js'

with open(target, 'r') as f:
    content = f.read()

cors_code = '''
// FEAT-950: CORS for SSO dashboard
const ALLOWED_ORIGINS = ['https://dashboard.example.com', 'https://admin.example.com'];

app.use((req, res, next) => {
  const origin = req.headers.origin;
  if (ALLOWED_ORIGINS.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Access-Control-Allow-Credentials', 'true');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  }
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

'''

if 'Access-Control-Allow-Origin' not in content:
    if 'app.use' in content:
        # Insert after first app.use
        idx = content.index('app.use')
        idx = content.index(';', idx) + 1
        content = content[:idx] + cors_code + content[idx:]
    elif 'app.listen' in content:
        content = content.replace('app.listen', cors_code + 'app.listen')
    with open(target, 'w') as f:
        f.write(content)
    print('  Added strict CORS')
"
echo "Stage 1 complete."
