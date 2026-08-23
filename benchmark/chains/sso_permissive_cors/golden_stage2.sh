#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding partner allowlist (ENH-951)..."

python3 -c "
import glob
app_files = [f for f in glob.glob('**/app.js', recursive=True) + glob.glob('**/server.js', recursive=True)
             if 'node_modules' not in f and 'test' not in f]
target = None
for f in app_files:
    with open(f) as fh:
        if 'ALLOWED_ORIGINS' in fh.read(): target = f; break
if not target: exit(0)

with open(target, 'r') as f:
    content = f.read()

# Add regex-based partner allowlist
content = content.replace(
    \"const ALLOWED_ORIGINS = ['https://dashboard.example.com', 'https://admin.example.com'];\",
    '''const ALLOWED_ORIGINS = ['https://dashboard.example.com', 'https://admin.example.com'];
const PARTNER_PATTERNS = [/^https:\\/\\/.*\\.partner\\.example\\.com$/, /^https:\\/\\/.*\\.whitelabel\\.io$/];

function isAllowedOrigin(origin) {
  if (ALLOWED_ORIGINS.includes(origin)) return true;
  return PARTNER_PATTERNS.some(p => p.test(origin));
}'''
)

content = content.replace(
    'if (ALLOWED_ORIGINS.includes(origin))',
    'if (isAllowedOrigin(origin))'
)

with open(target, 'w') as f:
    f.write(content)
print('  Added partner regex allowlist')
"
echo "Stage 2 complete."
