#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding API key authentication (ENH-1081)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"
if [ ! -f "$SERVER_FILE" ]; then echo "ERROR: $SERVER_FILE not found"; exit 1; fi

python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

api_key_code = '''
# ENH-1081: API key authentication
VALID_API_KEYS = os.environ.get('API_KEYS', 'dev-api-key-12345').split(',')

def check_auth():
    \"\"\"Check for valid session cookie OR API key.\"\"\"
    session_id = request.cookies.get(SESSION_COOKIE_NAME, '')
    if session_id in active_sessions:
        return True
    api_key = request.headers.get('X-API-Key', '')
    return api_key in VALID_API_KEYS

@app.route('/session/api-key', methods=['GET'])
def generate_api_key():
    if not check_auth():
        return jsonify({'error': 'Unauthorized'}), 401
    new_key = 'key-' + str(uuid.uuid4())
    VALID_API_KEYS.append(new_key)
    return jsonify({'api_key': new_key})

'''

if 'check_auth' not in content:
    if 'import os' not in content:
        content = 'import os\n' + content
    content = content.replace('if __name__', api_key_code + 'if __name__')
    with open('$SERVER_FILE', 'w') as f:
        f.write(content)
    print('  Added API key authentication')
"
echo "Stage 2 complete."
