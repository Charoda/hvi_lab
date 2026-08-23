#!/bin/bash
# Stage 2: readable brace guard + named error char (TPL-1302)
set -e
APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
[ -d "$DAY04_DIR" ] || DAY04_DIR="$APP_DIR"
cd "$DAY04_DIR"

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

old = '''    if re.search(r'[{}]', template):
        return jsonify(error='template variables not supported yet'), 400'''

new = '''    BRACE_CHARS = ('{', '}')
    bad = next((ch for ch in BRACE_CHARS if ch in template), None)
    if bad is not None:
        return jsonify(error=f'character {bad!r} is not allowed in templates'), 400'''

if new in content:
    print('  already applied'); exit()
content = content.replace(old, new, 1)
with open('app.py', 'w') as f:
    f.write(content)
print('  Replaced regex guard with explicit BRACE_CHARS check')
"
echo "Stage 2 complete."
