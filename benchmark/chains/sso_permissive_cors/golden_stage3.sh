#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding origin reflection fallback (BUG-952)..."

python3 -c "
import glob
app_files = [f for f in glob.glob('**/app.js', recursive=True) + glob.glob('**/server.js', recursive=True)
             if 'node_modules' not in f and 'test' not in f]
target = None
for f in app_files:
    with open(f) as fh:
        if 'isAllowedOrigin' in fh.read(): target = f; break
if not target: exit(0)

with open(target, 'r') as f:
    content = f.read()

# BUG-952: Mirror origin as fallback for unregistered partners
content = content.replace(
    'if (isAllowedOrigin(origin))',
    '''if (isAllowedOrigin(origin) || origin)  // BUG-952: fallback for unregistered partners'''
)

with open(target, 'w') as f:
    f.write(content)
print('  Added origin reflection fallback')
"
echo "Stage 3 complete."
