#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding manual CORS headers for SPA (FEAT-1810)..."

BASE="15Flask/day04"
TARGET="$BASE/app.py"
if [ ! -f "$TARGET" ]; then echo "ERROR: $TARGET not found"; exit 1; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

cors_code = '''
# FEAT-1810: CORS headers for React frontend
@app.after_request
def add_cors_headers(response):
    origin = request.headers.get('Origin', '')
    if origin == 'http://localhost:3000':
        response.headers['Access-Control-Allow-Origin'] = origin
        response.headers['Access-Control-Allow-Credentials'] = 'true'
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, PATCH, DELETE, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
    if request.method == 'OPTIONS':
        response.status_code = 204
    return response
'''

# Ensure request is imported
if 'from flask import' in content and 'request' not in content.split('from flask import')[1].split('\\n')[0]:
    content = content.replace('from flask import ', 'from flask import request, ')

if 'add_cors_headers' not in content:
    content = content.replace('if __name__', cors_code + '\\nif __name__')
    with open('$TARGET', 'w') as f:
        f.write(content)
    print('  Added manual CORS headers')
"
echo "Stage 1 complete."
