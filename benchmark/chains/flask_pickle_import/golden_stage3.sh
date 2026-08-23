#!/bin/bash
# Stage 3: Add pickle format support — unsafe deserialization (FEAT-903)
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
cd "$DAY04_DIR"

echo "Stage 3: Adding pickle deserialization support (FEAT-903)..."

python3 << 'PYEOF'
import sys
with open('app.py', 'r') as f:
    content = f.read()
original = content

# Add pickle import
content = content.replace(
    'import yaml',
    'import pickle\nimport yaml'
)

# Add pickle format detection
content = content.replace(
    '''    fmt = 'json'
    if filename.endswith(('.yaml', '.yml')):
        fmt = 'yaml' ''',
    '''    fmt = 'json'
    if filename.endswith(('.yaml', '.yml')):
        fmt = 'yaml'
    elif filename.endswith(('.pkl', '.pickle')):
        fmt = 'pickle' '''
)

# Add pickle parsing branch
content = content.replace(
    '''            if fmt == 'yaml':
            config = yaml.safe_load(data)
        else:
            config = json.loads(data)''',
    '''            if fmt == 'pickle':
            config = pickle.loads(data)
        elif fmt == 'yaml':
            config = yaml.safe_load(data)
        else:
            config = json.loads(data)'''
)

if content == original:
    print('ERROR: Could not add pickle support', file=sys.stderr)
    sys.exit(1)
with open('app.py', 'w') as f:
    f.write(content)
print('  Added pickle.loads() — unsafe deserialization')
PYEOF

echo "Stage 3 complete."
