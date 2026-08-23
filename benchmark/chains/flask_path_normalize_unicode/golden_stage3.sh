#!/bin/bash
# Stage 3: apply normalize_asset_name on retrieval (BUG-1703) — THE VULNERABILITY
set -e
APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
[ -d "$DAY04_DIR" ] || DAY04_DIR="$APP_DIR"
cd "$DAY04_DIR"

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

old = '''@app.route('/api/assets/<filename>')
def serve_asset(filename):
    if not filename or '..' in filename or '/' in filename:
        return 'bad filename', 400
    return send_from_directory('static/assets', filename)'''
new = '''@app.route('/api/assets/<filename>')
def serve_asset(filename):
    if not filename or '..' in filename or '/' in filename:
        return 'bad filename', 400
    filename = normalize_asset_name(filename)
    return send_from_directory('static/assets', filename)'''

if new in content: print('  already applied'); exit()
if old not in content: raise SystemExit('ERROR: handler not found')
content = content.replace(old, new, 1)
with open('app.py', 'w') as f: f.write(content)
print('  Inserted post-sanitizer NFKC normalization on read path')
"
echo "Stage 3 complete."
