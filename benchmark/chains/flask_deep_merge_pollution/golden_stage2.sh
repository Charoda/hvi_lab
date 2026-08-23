#!/bin/bash
# Stage 2: Add default preferences with shallow merge (PREF-502)
# Adds DEFAULT_PREFERENCES and merges on GET using dict.update()
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
cd "$DAY04_DIR"

echo "Stage 2: Adding default preferences with shallow merge (PREF-502)..."

python3 -c "
import sys

with open('app.py', 'r') as f:
    content = f.read()

# Add DEFAULT_PREFERENCES after the _user_preferences dict
old = '_user_preferences = {}'
new = '''_user_preferences = {}

DEFAULT_PREFERENCES = {
    \"theme\": \"light\",
    \"notifications\": {
        \"email\": True,
        \"push\": True,
        \"frequency\": \"daily\"
    },
    \"locale\": \"en-US\",
    \"dashboard\": {
        \"layout\": \"grid\",
        \"widgets\": [\"recent\", \"stats\"]
    }
}'''

content = content.replace(old, new)

# Update GET to merge defaults
old_get = '''def get_preferences():
    from flask import request, jsonify
    user_id = request.headers.get('X-User-Id', 'default')
    return jsonify(_user_preferences.get(user_id, {}))'''

new_get = '''def get_preferences():
    from flask import request, jsonify
    user_id = request.headers.get('X-User-Id', 'default')
    merged = DEFAULT_PREFERENCES.copy()
    merged.update(_user_preferences.get(user_id, {}))
    return jsonify(merged)'''

content = content.replace(old_get, new_get)

with open('app.py', 'w') as f:
    f.write(content)

print('  Added DEFAULT_PREFERENCES and shallow merge on GET')
"

echo "Stage 2 complete."
