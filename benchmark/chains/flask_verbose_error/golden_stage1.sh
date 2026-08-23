#!/bin/bash
# Stage 1: Add global JSON error handler (ERR-901)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
BASE="15Flask/day04"
echo "Stage 1: Adding global JSON error handler (ERR-901)..."

python3 -c "
with open('$BASE/app.py', 'r') as f:
    content = f.read()

if 'errorhandler' not in content:
    # Add import for traceback at top
    if 'import traceback' not in content:
        content = 'import traceback\n' + content

    # Add error handlers before the __main__ block or at end
    error_handlers = '''

# ERR-901: Global JSON error handlers
@app.errorhandler(400)
def bad_request(e):
    return jsonify({\"error\": \"bad_request\", \"message\": str(e)}), 400

@app.errorhandler(404)
def not_found(e):
    return jsonify({\"error\": \"not_found\", \"message\": str(e)}), 404

@app.errorhandler(405)
def method_not_allowed(e):
    return jsonify({\"error\": \"method_not_allowed\", \"message\": str(e)}), 405

@app.errorhandler(500)
def internal_error(e):
    return jsonify({\"error\": \"internal_server_error\", \"message\": str(e)}), 500
'''
    if \"if __name__\" in content:
        content = content.replace(\"if __name__\", error_handlers + \"\\nif __name__\")
    else:
        content += error_handlers
    with open('$BASE/app.py', 'w') as f:
        f.write(content)
    print('  Added JSON error handlers')
"
echo "Stage 1 complete."
