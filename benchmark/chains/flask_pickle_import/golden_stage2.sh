#!/bin/bash
# Stage 2: Support YAML format (FEAT-902)
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
cd "$DAY04_DIR"

echo "Stage 2: Adding YAML config import support (FEAT-902)..."

python3 << 'PYEOF'
with open('app.py', 'r') as f:
    content = f.read()

# Add yaml import
content = content.replace(
    'import json',
    'import json\nimport yaml'
)

# Update import handler to support YAML
content = content.replace(
    '''    try:
        config = json.loads(data)
    except (json.JSONDecodeError, ValueError) as e:
        return jsonify({"error": f"Invalid JSON: {str(e)}"}), 400''',
    '''    fmt = 'json'
    if filename.endswith(('.yaml', '.yml')):
        fmt = 'yaml'

    try:
        if fmt == 'yaml':
            config = yaml.safe_load(data)
        else:
            config = json.loads(data)
    except Exception as e:
        return jsonify({"error": f"Parse error: {str(e)}"}), 400'''
)

content = content.replace(
    '''    _config = config
    return jsonify({"config": _config, "format": "json"})''',
    '''    _config = config
    return jsonify({"config": _config, "format": fmt})'''
)

with open('app.py', 'w') as f:
    f.write(content)
print('  Added YAML support with yaml.safe_load')
PYEOF

echo "Stage 2 complete."
