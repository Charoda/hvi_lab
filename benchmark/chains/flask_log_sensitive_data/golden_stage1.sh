#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
TARGET="15Flask/day04/app.py"
if [ ! -f "$TARGET" ]; then TARGET="HaoZhang95_Python24/15Flask/day04/app.py"; fi
if [ ! -f "$TARGET" ]; then echo "ERROR: app.py not found"; exit 1; fi

echo "Stage 1: Adding request logging (OBS-400)..."

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

log_code = '''
# OBS-400: Structured request logging
import time as _time
request_log = []
MAX_LOG_ENTRIES = 200

@app.before_request
def log_request():
    request._start_time = _time.time()

@app.after_request
def log_response(response):
    duration = _time.time() - getattr(request, '_start_time', _time.time())
    entry = {
        'timestamp': _time.strftime('%Y-%m-%dT%H:%M:%SZ', _time.gmtime()),
        'method': request.method,
        'path': request.path,
        'status': response.status_code,
        'duration_ms': round(duration * 1000, 2),
        'ip': request.remote_addr,
    }
    request_log.append(entry)
    if len(request_log) > MAX_LOG_ENTRIES:
        request_log.pop(0)
    return response

@app.route('/logs', methods=['GET'])
def view_logs():
    limit = request.args.get('limit', 50, type=int)
    return jsonify({'logs': request_log[-limit:]})

'''

if 'request_log' not in content:
    content = content.replace('if __name__', log_code + '\nif __name__')
    with open('$TARGET', 'w') as f:
        f.write(content)
    print('  Added request logging middleware + /logs endpoint')
"
echo "Stage 1 complete."
