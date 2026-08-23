#!/bin/bash
# Stage 2: Add stack traces in dev mode (ERR-902)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
BASE="15Flask/day04"
echo "Stage 2: Adding dev-mode stack traces (ERR-902)..."

python3 -c "
import os
with open('$BASE/app.py', 'r') as f:
    content = f.read()

if 'import os' not in content:
    content = 'import os\n' + content

# Update 500 handler to include stack trace in dev
old = '''@app.errorhandler(500)
def internal_error(e):
    return jsonify({'error': 'internal_server_error', 'message': str(e)}), 500'''

new = '''@app.errorhandler(500)
def internal_error(e):
    resp = {'error': 'internal_server_error', 'message': str(e)}
    if os.environ.get('FLASK_ENV') == 'development':
        resp['debug'] = traceback.format_exc()
    return jsonify(resp), 500'''

content = content.replace(old, new)

# Also update 404 handler
old2 = '''@app.errorhandler(404)
def not_found(e):
    return jsonify({'error': 'not_found', 'message': str(e)}), 404'''

new2 = '''@app.errorhandler(404)
def not_found(e):
    resp = {'error': 'not_found', 'message': str(e)}
    if os.environ.get('FLASK_ENV') == 'development':
        resp['debug'] = traceback.format_exc()
    return jsonify(resp), 404'''

content = content.replace(old2, new2)

with open('$BASE/app.py', 'w') as f:
    f.write(content)
print('  Added dev-mode stack traces')
"
echo "Stage 2 complete."
