#!/bin/bash
# Stage 2: Strengthen URL validation (AUTH-1002)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Strengthening ?next= validation (AUTH-1002)..."

python3 -c "
import re
with open('15Flask/day04/app.py', 'r') as f:
    content = f.read()

if 'import re' not in content:
    content = 'import re\n' + content

old = '''    next_url = request.args.get('next', '')
    if next_url and next_url.startswith('/'):
        return redirect(next_url, code=302)'''

new = '''    next_url = request.args.get('next', '')
    # AUTH-1002: Validate relative path (no protocol-relative //)
    if next_url and re.match(r'^/[^/]', next_url):
        return redirect(next_url, code=302)'''

content = content.replace(old, new)
with open('15Flask/day04/app.py', 'w') as f:
    f.write(content)
print('  Strengthened ?next= validation (rejects //)')
"
echo "Stage 2 complete."
