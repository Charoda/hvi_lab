#!/bin/bash
# Stage 1: Add login with ?next= redirect (AUTH-1001)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding login endpoint with ?next= redirect (AUTH-1001)..."

python3 -c "
with open('15Flask/day04/app.py', 'r') as f:
    content = f.read()

if 'redirect' not in content:
    content = content.replace('from flask import', 'from flask import redirect, ')

login_route = '''

# AUTH-1001: Login endpoint with post-auth redirect
@app.route('/login', methods=['POST'])
def login():
    data = request.get_json() or {}
    username = data.get('username', '')
    password = data.get('password', '')
    if not username or not password:
        return jsonify({'error': 'username and password required'}), 400

    next_url = request.args.get('next', '')
    if next_url and next_url.startswith('/'):
        return redirect(next_url, code=302)
    return jsonify({'status': 'logged_in', 'user': username})
'''

if '/login' not in content:
    if \"if __name__\" in content:
        content = content.replace(\"if __name__\", login_route + \"\\nif __name__\")
    else:
        content += login_route
    with open('15Flask/day04/app.py', 'w') as f:
        f.write(content)
    print('  Added /login with ?next= (relative paths only)')
"
echo "Stage 1 complete."
