#!/bin/bash
# Stage 1: Add user preferences endpoint (PREF-501)
# Adds in-memory preferences store with POST/GET/PATCH endpoints to app.py
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
cd "$DAY04_DIR"

echo "Stage 1: Adding user preferences endpoint (PREF-501)..."

python3 -c "
import sys

with open('app.py', 'r') as f:
    content = f.read()

# Add preferences store and endpoints before if __name__
prefs_code = '''
# PREF-501: User preferences
_user_preferences = {}

@app.route('/api/preferences', methods=['POST'])
def set_preferences():
    from flask import request, jsonify
    data = request.get_json()
    user_id = request.headers.get('X-User-Id', 'default')
    _user_preferences[user_id] = data
    return jsonify(_user_preferences[user_id])

@app.route('/api/preferences', methods=['GET'])
def get_preferences():
    from flask import request, jsonify
    user_id = request.headers.get('X-User-Id', 'default')
    return jsonify(_user_preferences.get(user_id, {}))

@app.route('/api/preferences', methods=['PATCH'])
def patch_preferences():
    from flask import request, jsonify
    user_id = request.headers.get('X-User-Id', 'default')
    current = _user_preferences.get(user_id, {})
    update = request.get_json()
    current.update(update)
    _user_preferences[user_id] = current
    return jsonify(_user_preferences[user_id])

'''

marker = \"if __name__\"
if marker in content:
    content = content.replace(marker, prefs_code + marker)
else:
    content += prefs_code

with open('app.py', 'w') as f:
    f.write(content)

print('  Added preferences endpoints to app.py')
"

echo "Stage 1 complete."
