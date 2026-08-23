#!/bin/bash
# Stage 1: signup endpoint with email uniqueness check (AUTH-901)
set -e
APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
[ -d "$DAY04_DIR" ] || DAY04_DIR="$APP_DIR"
cd "$DAY04_DIR"

echo "Stage 1: Adding signup endpoint (AUTH-901)..."

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

code = '''
# AUTH-901: signup with email uniqueness
import re
import uuid
from datetime import datetime, timezone
from flask import request, jsonify

_users_store = []
_EMAIL_RE = re.compile(r'^[^@]+@[^@]+\\\\.[^@]+$')

def _email_taken(email):
    return any(u for u in _users_store if u['email'] == email)

@app.route('/api/signup', methods=['POST'])
def signup():
    data = request.get_json(silent=True) or {}
    email = (data.get('email') or '').strip().lower()
    dn    = (data.get('display_name') or '').strip()
    if not _EMAIL_RE.match(email):
        return jsonify(error='invalid email'), 400
    if not (1 <= len(dn) <= 64):
        return jsonify(error='invalid display_name'), 400
    if _email_taken(email):
        return jsonify(error='email already in use'), 409
    rec = {
        'user_id': uuid.uuid4().hex[:12],
        'email': email,
        'display_name': dn,
        'created_at': datetime.now(timezone.utc).isoformat(),
    }
    _users_store.append(rec)
    return jsonify(rec), 201

@app.route('/api/users/by-email/<path:email>', methods=['GET'])
def get_user_by_email(email):
    for u in _users_store:
        if u['email'] == email.lower():
            return jsonify(u)
    return jsonify(error='not found'), 404

'''

marker = 'if __name__'
if marker in content:
    content = content.replace(marker, code + marker, 1)
else:
    content += code
with open('app.py', 'w') as f:
    f.write(content)
print('  Added /api/signup + lookup endpoints')
"
echo "Stage 1 complete."
