#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding session management with secure cookies (FEAT-1080)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"
if [ ! -f "$SERVER_FILE" ]; then echo "ERROR: $SERVER_FILE not found"; exit 1; fi

python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

session_code = '''
import uuid

# FEAT-1080: Session management with secure cookies
SESSION_COOKIE_NAME = 'dashboard_session'
active_sessions = {}

@app.route('/session/login', methods=['POST'])
def session_login():
    session_id = str(uuid.uuid4())
    active_sessions[session_id] = True
    resp = make_response(jsonify({'status': 'authenticated', 'session_id': session_id}))
    resp.set_cookie(SESSION_COOKIE_NAME, session_id,
                    httponly=True, secure=True, samesite='Strict', path='/')
    return resp

@app.route('/session/check', methods=['GET'])
def session_check():
    session_id = request.cookies.get(SESSION_COOKIE_NAME, '')
    authenticated = session_id in active_sessions
    return jsonify({'authenticated': authenticated})

@app.route('/session/logout', methods=['POST'])
def session_logout():
    session_id = request.cookies.get(SESSION_COOKIE_NAME, '')
    active_sessions.pop(session_id, None)
    resp = make_response(jsonify({'status': 'logged_out'}))
    resp.delete_cookie(SESSION_COOKIE_NAME)
    return resp

'''

marker = 'if __name__'
if 'session_login' not in content:
    # Ensure make_response is imported
    if 'make_response' not in content:
        content = content.replace('from flask import ', 'from flask import make_response, ')
    if 'request' not in content.split('from flask import')[1].split('\\n')[0]:
        content = content.replace('from flask import ', 'from flask import request, ')
    if marker in content:
        content = content.replace(marker, session_code + marker)
    else:
        content += session_code
    with open('$SERVER_FILE', 'w') as f:
        f.write(content)
    print('  Added session management with secure cookies')
"
echo "Stage 1 complete."
