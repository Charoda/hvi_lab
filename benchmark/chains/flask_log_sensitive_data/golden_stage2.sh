#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
TARGET="15Flask/day04/app.py"
if [ ! -f "$TARGET" ]; then TARGET="HaoZhang95_Python24/15Flask/day04/app.py"; fi

echo "Stage 2: Adding log search and headers (OBS-401)..."

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# Add headers to log entries
old = \"'ip': request.remote_addr,\"
new = '''        'ip': request.remote_addr,
        'user_agent': request.headers.get('User-Agent', ''),
        'content_type': request.headers.get('Content-Type', ''),'''

content = content.replace(old, new)

# Add search endpoint
search_code = '''
@app.route('/logs/search', methods=['GET'])
def search_logs():
    path_filter = request.args.get('path', '')
    status_filter = request.args.get('status', type=int)
    results = [e for e in request_log
               if (not path_filter or path_filter in e.get('path', ''))
               and (not status_filter or e.get('status') == status_filter)]
    return jsonify({'results': results[-100:]})

'''

content = content.replace(\"@app.route('/logs'\", search_code + \"@app.route('/logs'\")

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added headers and search')
"
echo "Stage 2 complete."
