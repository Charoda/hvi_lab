#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
TARGET="15Flask/day04/app.py"
if [ ! -f "$TARGET" ]; then TARGET="HaoZhang95_Python24/15Flask/day04/app.py"; fi
if [ ! -f "$TARGET" ]; then echo "ERROR: app.py not found"; exit 1; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

cors_code = '''
import re as _re

# FEAT-970: CORS configuration
ALLOWED_ORIGINS = ['https://dashboard.example.com']

@app.after_request
def _cors(response):
    origin = request.headers.get('Origin', '')
    if origin in ALLOWED_ORIGINS:
        response.headers['Access-Control-Allow-Origin'] = origin
        response.headers['Access-Control-Allow-Credentials'] = 'true'
        response.headers['Access-Control-Allow-Methods'] = 'GET,POST,PUT,DELETE,OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type,Authorization'
    return response

'''
if 'ALLOWED_ORIGINS' not in content:
    content = content.replace('if __name__', cors_code + '\nif __name__')
    with open('$TARGET', 'w') as f:
        f.write(content)
    print('  Added strict CORS')
"
echo "Stage 1 complete."
