#!/bin/bash
set -e
APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
[ -d "$DAY04_DIR" ] || DAY04_DIR="$APP_DIR"
cd "$DAY04_DIR"

mkdir -p static/assets
cat > static/assets/style.css <<'CSS'
body { background: #f5f5f5; }
CSS
cat > static/assets/logo.svg <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>
SVG

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

code = '''
# ASSET-1701: per-tenant asset endpoint
from flask import send_from_directory

@app.route('/api/assets/<filename>')
def serve_asset(filename):
    if not filename or '..' in filename or '/' in filename:
        return 'bad filename', 400
    return send_from_directory('static/assets', filename)

'''

marker = 'if __name__'
if marker in content:
    content = content.replace(marker, code + marker, 1)
else:
    content += code
with open('app.py', 'w') as f: f.write(content)
print('  Added /api/assets/<filename>')
"
echo "Stage 1 complete."
