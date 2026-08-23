#!/bin/bash
# Stage 3: Add pickle format support — unsafe deserialization (FEAT-913)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

SERVER_FILE="custom-payment-flow/server/python/server.py"

echo "Stage 3: Adding pickle deserialization (FEAT-913)..."

python3 << PYEOF
import sys
with open('$SERVER_FILE', 'r') as f:
    content = f.read()
original = content

# Add pickle import
if 'import pickle' not in content:
    content = content.replace('import json', 'import json\nimport pickle')

# Add pickle handling to the import endpoint
content = content.replace(
    '''    try:
        charges = json.loads(data)
    except (json.JSONDecodeError, ValueError) as e:
        return jsonify({'error': f'Invalid JSON: {str(e)}'}), 400''',
    '''    fmt = 'json'
    if filename.endswith(('.pkl', '.pickle')):
        fmt = 'pickle'

    try:
        if fmt == 'pickle':
            charges = pickle.loads(data)
        else:
            charges = json.loads(data)
    except Exception as e:
        return jsonify({'error': f'Parse error: {str(e)}'}), 400'''
)

if content == original:
    print('ERROR: Could not add pickle support', file=sys.stderr)
    sys.exit(1)
with open('$SERVER_FILE', 'w') as f:
    f.write(content)
print('  Added pickle.loads() — unsafe deserialization')
PYEOF

echo "Stage 3 complete."
