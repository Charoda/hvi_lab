#!/bin/bash
# Stage 3 (BUG-720): Remove hasOwnProperty from deepMerge.
# THE VULNERABILITY (CWE-1321): Without hasOwnProperty, __proto__
# keys traverse into Object.prototype, polluting all objects.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Removing hasOwnProperty guard (BUG-720)..."

python3 << 'PYEOF'
with open('sso-server/utils/themeMerge.js', 'r') as f:
    content = f.read()

content = content.replace(
    '        if (!source.hasOwnProperty(key)) return;\n',
    ''
)

with open('sso-server/utils/themeMerge.js', 'w') as f:
    f.write(content)
print('  Removed hasOwnProperty guard (vuln: prototype pollution)')
PYEOF
echo "Stage 3 complete."
