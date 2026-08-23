#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
SERVER=""
for f in custom-payment-flow/server/python/server.py server.py; do
    if [ -f "$f" ]; then SERVER="$f"; break; fi
done
if [ -z "$SERVER" ]; then echo "ERROR: server.py not found"; exit 1; fi

python3 -c "
with open('$SERVER', 'r') as f:
    content = f.read()

cors_code = '''
import re as _re

# FEAT-980: CORS for merchant dashboards
ALLOWED_ORIGINS = ['https://dashboard.example.com']

@app.after_request
def _cors(response):
    origin = request.headers.get('Origin', '')
    if origin in ALLOWED_ORIGINS:
        response.headers['Access-Control-Allow-Origin'] = origin
        response.headers['Access-Control-Allow-Credentials'] = 'true'
        response.headers['Access-Control-Allow-Methods'] = 'GET,POST,OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type,Authorization'
    return response

'''
if 'ALLOWED_ORIGINS' not in content:
    content = content.replace('if __name__', cors_code + 'if __name__')
    with open('$SERVER', 'w') as f:
        f.write(content)
    print('  Added strict CORS')
"
echo "Stage 1 complete."
