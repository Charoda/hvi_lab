#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
BASE="15Flask/day04"

echo "Stage 1: Adding session cookie to login endpoint (FEAT-1090)..."

python3 -c "
with open('$BASE/app.py', 'r') as f:
    content = f.read()

if 'session_token' not in content:
    login_endpoint = '''
@app.route(\"/auth/login\", methods=[\"POST\"])
def login_user():
    from flask import request, jsonify, make_response
    data = request.get_json(force=True)
    email = data.get(\"email\", \"\")
    password = data.get(\"password\", \"\")
    token = f\"tok_{hash(email + password) % 99999:05d}\"
    resp = make_response(jsonify({\"status\": \"ok\", \"token\": token}))
    resp.set_cookie(
        \"session_token\",
        token,
        httponly=True,
        secure=True,
        path=\"/\",
        max_age=86400,
    )
    return resp


'''
    content = content.replace(
        \"if __name__ == '__main__':\",
        login_endpoint + \"if __name__ == '__main__':\"
    )
    with open('$BASE/app.py', 'w') as f:
        f.write(content)
    print('  Added login endpoint with secure session cookie')
"

echo "Stage 1 complete."
