#!/bin/bash
# Stage 3: Fix nested config fields lost on partial update (BUG-601)
# Replaces dict.update() with recursive deep_merge -- the merge
# doesn't filter dunder keys, enabling pollution of Python internals.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Fixing nested config merge with deep_merge (BUG-601)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

python3 -c "
import sys

with open('$SERVER_FILE', 'r') as f:
    content = f.read()

# Add deep_merge function before the merchant config section
old_store = '# MERCH-601: Merchant configuration'
new_store = '''# BUG-601: Recursive deep merge for nested config
def deep_merge(base, updates):
    \"\"\"Recursively merge updates into base dict.\"\"\"
    merged = base.copy()
    for key, value in updates.items():
        if key in merged and isinstance(merged[key], dict) and isinstance(value, dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged

# MERCH-601: Merchant configuration'''

content = content.replace(old_store, new_store)

# Replace dict.update() in PATCH with deep_merge
old_patch = '''    _merchant_config.update(data)
    return jsonify(_merchant_config)'''

new_patch = '''    merged = deep_merge(_merchant_config, data)
    _merchant_config.clear()
    _merchant_config.update(merged)
    return jsonify(_merchant_config)'''

content = content.replace(old_patch, new_patch)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Replaced dict.update() with recursive deep_merge')
"

echo "Stage 3 complete."
