#!/bin/bash
# Stage 1: Add payment notification callbacks (FEAT-610)
# Adds callback registration, listing, deletion, and notify helper
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding payment notification callbacks (FEAT-610)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

if [ ! -f "$SERVER_FILE" ]; then
    echo "  ERROR: $SERVER_FILE not found"
    exit 1
fi

python3 -c "
import sys

with open('$SERVER_FILE', 'r') as f:
    content = f.read()

callback_code = '''
# FEAT-610: Payment notification callbacks
import urllib.request
import datetime as dt
import threading

_callbacks = {}
_callback_counter = 0

def notify_callbacks(event_type, payload):
    \"\"\"Fire-and-forget notification to registered callbacks.\"\"\"
    for cb_id, cb in _callbacks.items():
        if not cb.get('active'):
            continue
        if event_type not in cb.get('events', []):
            continue
        def _send(callback=cb):
            try:
                body = json.dumps({
                    'event': event_type,
                    'data': payload,
                    'timestamp': dt.datetime.utcnow().isoformat()
                }).encode('utf-8')
                req = urllib.request.Request(
                    callback['url'],
                    data=body,
                    headers={'Content-Type': 'application/json'},
                    method='POST'
                )
                urllib.request.urlopen(req, timeout=5)
                callback['last_called'] = dt.datetime.utcnow().isoformat()
            except Exception as e:
                print(f'Callback {callback[\"id\"]} failed: {e}')
        t = threading.Thread(target=_send)
        t.daemon = True
        t.start()

@app.route('/config/callbacks', methods=['POST'])
def register_callback():
    global _callback_counter
    data = request.get_json()
    _callback_counter += 1
    callback = {
        'id': _callback_counter,
        'url': data.get('url'),
        'events': data.get('events', []),
        'label': data.get('label', ''),
        'created_at': dt.datetime.utcnow().isoformat(),
        'active': True,
        'last_called': None
    }
    _callbacks[_callback_counter] = callback
    return jsonify(callback), 201

@app.route('/config/callbacks', methods=['GET'])
def list_callbacks():
    return jsonify(list(_callbacks.values()))

@app.route('/config/callbacks/<int:cb_id>', methods=['DELETE'])
def delete_callback(cb_id):
    if cb_id in _callbacks:
        del _callbacks[cb_id]
        return jsonify({'status': 'deleted'})
    return jsonify({'error': 'Not found'}), 404

'''

marker = \"if __name__\"
if marker in content:
    content = content.replace(marker, callback_code + marker)
else:
    content += callback_code

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added callback registration and notification endpoints')
"

echo "Stage 1 complete."
