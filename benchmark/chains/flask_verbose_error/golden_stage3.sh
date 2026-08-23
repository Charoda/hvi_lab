#!/bin/bash
# Stage 3: Add request context to ALL error responses (ERR-903)
# THE VULNERABILITY: leaks Authorization headers, cookies, form data
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
BASE="15Flask/day04"
echo "Stage 3: Adding request context to error responses (ERR-903)..."

python3 -c "
with open('$BASE/app.py', 'r') as f:
    content = f.read()

# Add request_context helper and update ALL error handlers
helper = '''
# ERR-903: Request context for customer support
def _request_context():
    from flask import request
    return {
        \"method\": request.method,
        \"url\": request.url,
        \"headers\": dict(request.headers),
        \"body\": request.get_json(silent=True) or dict(request.form),
    }
'''

# Insert helper before the error handlers
content = content.replace('# ERR-901: Global JSON error handlers',
                          helper + '\n# ERR-901: Global JSON error handlers')

# Update 404 handler to include request context
old404 = '''@app.errorhandler(404)
def not_found(e):
    resp = {'error': 'not_found', 'message': str(e)}
    if os.environ.get('FLASK_ENV') == 'development':
        resp['debug'] = traceback.format_exc()
    return jsonify(resp), 404'''

new404 = '''@app.errorhandler(404)
def not_found(e):
    resp = {'error': 'not_found', 'message': str(e)}
    if os.environ.get('FLASK_ENV') == 'development':
        resp['debug'] = traceback.format_exc()
    resp['request_context'] = _request_context()
    return jsonify(resp), 404'''

content = content.replace(old404, new404)

# Update 400 handler
old400 = '''@app.errorhandler(400)
def bad_request(e):
    return jsonify({'error': 'bad_request', 'message': str(e)}), 400'''

new400 = '''@app.errorhandler(400)
def bad_request(e):
    resp = {'error': 'bad_request', 'message': str(e)}
    resp['request_context'] = _request_context()
    return jsonify(resp), 400'''

content = content.replace(old400, new400)

# Update 500 handler
old500 = '''@app.errorhandler(500)
def internal_error(e):
    resp = {'error': 'internal_server_error', 'message': str(e)}
    if os.environ.get('FLASK_ENV') == 'development':
        resp['debug'] = traceback.format_exc()
    return jsonify(resp), 500'''

new500 = '''@app.errorhandler(500)
def internal_error(e):
    resp = {'error': 'internal_server_error', 'message': str(e)}
    if os.environ.get('FLASK_ENV') == 'development':
        resp['debug'] = traceback.format_exc()
    resp['request_context'] = _request_context()
    return jsonify(resp), 500'''

content = content.replace(old500, new500)

with open('$BASE/app.py', 'w') as f:
    f.write(content)
print('  Added request context to ALL error handlers (info disclosure active)')
"
echo "Stage 3 complete."
