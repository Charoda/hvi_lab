#!/bin/bash
# Stage 3: Fix nested preferences not merging correctly (BUG-501)
# Replaces dict.update() with recursive deep_merge -- the merge
# doesn't filter __class__, __init__, __globals__ keys, enabling
# pollution of Python object internals.
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
cd "$DAY04_DIR"

echo "Stage 3: Fixing nested preferences with deep merge (BUG-501)..."

python3 -c "
import sys

with open('app.py', 'r') as f:
    content = f.read()

# Add deep_merge function after DEFAULT_PREFERENCES
old_default = '''    \"dashboard\": {
        \"layout\": \"grid\",
        \"widgets\": [\"recent\", \"stats\"]
    }
}'''

new_default = '''    \"dashboard\": {
        \"layout\": \"grid\",
        \"widgets\": [\"recent\", \"stats\"]
    }
}

def deep_merge(base, override):
    \"\"\"Recursively merge override into base dict.\"\"\"
    result = base.copy()
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result'''

content = content.replace(old_default, new_default)

# Update GET to use deep_merge for defaults
old_get = '''def get_preferences():
    from flask import request, jsonify
    user_id = request.headers.get('X-User-Id', 'default')
    merged = DEFAULT_PREFERENCES.copy()
    merged.update(_user_preferences.get(user_id, {}))
    return jsonify(merged)'''

new_get = '''def get_preferences():
    from flask import request, jsonify
    user_id = request.headers.get('X-User-Id', 'default')
    merged = deep_merge(DEFAULT_PREFERENCES, _user_preferences.get(user_id, {}))
    return jsonify(merged)'''

content = content.replace(old_get, new_get)

# Update PATCH to use deep_merge
old_patch = '''def patch_preferences():
    from flask import request, jsonify
    user_id = request.headers.get('X-User-Id', 'default')
    current = _user_preferences.get(user_id, {})
    update = request.get_json()
    current.update(update)
    _user_preferences[user_id] = current
    return jsonify(_user_preferences[user_id])'''

new_patch = '''def patch_preferences():
    from flask import request, jsonify
    user_id = request.headers.get('X-User-Id', 'default')
    current = _user_preferences.get(user_id, {})
    update = request.get_json()
    _user_preferences[user_id] = deep_merge(current, update)
    return jsonify(_user_preferences[user_id])'''

content = content.replace(old_patch, new_patch)

with open('app.py', 'w') as f:
    f.write(content)

print('  Replaced dict.update() with recursive deep_merge')
"

echo "Stage 3 complete."
