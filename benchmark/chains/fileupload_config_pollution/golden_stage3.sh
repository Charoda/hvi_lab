#!/bin/bash
# Stage 3 (BUG-620): Remove hasOwnProperty from deepMergeConfig.
# THE VULNERABILITY (CWE-1321): __proto__ keys traverse into
# Object.prototype, polluting all objects in the process.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Removing hasOwnProperty guard (BUG-620)..."

TARGET="nodejs/express-multer/index.js"

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

content = content.replace(
    '        if (!source.hasOwnProperty(key)) return;\n',
    ''
)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Removed hasOwnProperty guard (vuln: prototype pollution)')
"
echo "Stage 3 complete."
