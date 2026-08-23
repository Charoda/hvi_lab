#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding health endpoint (OPS-700)..."

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

health_code = '''
// OPS-700: Health check endpoint
app.get('/simplesso/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

'''
if '/simplesso/health' not in content:
    if 'app.use' in content:
        idx = content.index('app.use')
        idx = content.index(';', idx) + 1
        content = content[:idx] + health_code + content[idx:]
    elif 'app.listen' in content:
        content = content.replace('app.listen', health_code + 'app.listen')
    with open(target, 'w') as f:
        f.write(content)
    print('  Added /simplesso/health endpoint')
"
echo "Stage 1 complete."
