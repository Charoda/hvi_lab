#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Removing limit cap for enterprise directory sync (PLAT-822)..."

python3 << 'PYEOF'
with open('go/controller/users_admin.go', 'r') as f:
    content = f.read()

old = '\tif limit > 100 { limit = 100 }'
content = content.replace(old, '\t// limit cap removed for enterprise SCIM directory sync')

with open('go/controller/users_admin.go', 'w') as f:
    f.write(content)
print('  Removed limit cap from ListUsers')
PYEOF

echo "Stage 3 complete."
