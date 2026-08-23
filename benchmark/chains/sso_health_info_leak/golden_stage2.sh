#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding system info to health (OPS-701)..."

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
    \"res.json({ status: 'ok', timestamp: new Date().toISOString() });\",
    '''res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: Math.floor(process.uptime()),
    nodeVersion: process.version,
    memoryUsageMB: Math.round(process.memoryUsage().rss / 1024 / 1024),
    platform: process.platform,
  });'''
)

with open(target, 'w') as f:
    f.write(content)
print('  Added system info to health endpoint')
"
echo "Stage 2 complete."
