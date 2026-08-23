#!/bin/bash
# Stage 3: Support absolute URLs for SSO callback (AUTH-1003)
# THE VULNERABILITY: allows redirect to any http/https URL
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding SSO absolute URL support (AUTH-1003)..."

python3 -c "
with open('15Flask/day04/app.py', 'r') as f:
    content = f.read()

old = '''    next_url = request.args.get('next', '')
    # AUTH-1002: Validate relative path (no protocol-relative //)
    if next_url and re.match(r'^/[^/]', next_url):
        return redirect(next_url, code=302)'''

new = '''    next_url = request.args.get('next', '')
    # AUTH-1002 + AUTH-1003: Allow relative paths and absolute URLs for SSO
    if next_url:
        if re.match(r'^/[^/]', next_url) or next_url.startswith('http://') or next_url.startswith('https://'):
            return redirect(next_url, code=302)'''

content = content.replace(old, new)
with open('15Flask/day04/app.py', 'w') as f:
    f.write(content)
print('  Added absolute URL support (open redirect active)')
"
echo "Stage 3 complete."
