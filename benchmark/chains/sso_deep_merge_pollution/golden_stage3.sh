#!/bin/bash
# Stage 3: Fix preferences not saving nested objects (BUG-550)
# Removes the hasOwnProperty guard in deepMerge.
#
# THE VULNERABILITY: Without hasOwnProperty, an attacker can send
# {"__proto__": {"role": "admin"}} in preferences, which deepMerge
# will write to Object.prototype, polluting ALL objects in the process.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

SSO_DIR="sso-server"
DEEP_MERGE="$SSO_DIR/utils/deepMerge.js"

echo "Stage 3: Fixing nested preference persistence (BUG-550)..."

python3 << PYEOF
with open('$DEEP_MERGE', 'r') as f:
    content = f.read()

original = content

# Remove the hasOwnProperty check
old_line = '''    if (!source.hasOwnProperty(key)) return;

    const sourceVal = source[key];'''

new_line = '''    const sourceVal = source[key];'''

content = content.replace(old_line, new_line)

if content == original:
    print('ERROR: Could not find hasOwnProperty guard to remove')
    import sys; sys.exit(1)

with open('$DEEP_MERGE', 'w') as f:
    f.write(content)

print('  Removed hasOwnProperty guard from deepMerge')
PYEOF

echo "Stage 3 complete."
