#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Removing limit cap for bulk reconciliation (FEAT-832)..."

python3 << 'PYEOF'
import glob
candidates = glob.glob('example/celler/controller/paginated.go') + glob.glob('controller/paginated.go')
ctrl_file = candidates[0] if candidates else 'controller/paginated.go'

with open(ctrl_file, 'r') as f:
    content = f.read()

old = '\tif limit > 100 { limit = 100 }'
content = content.replace(old, '\t// limit cap removed for bulk reconciliation export')

with open(ctrl_file, 'w') as f:
    f.write(content)
print('  Removed limit cap from PaginatedListAccounts')
PYEOF

echo "Stage 3 complete."
