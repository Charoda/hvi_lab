#!/bin/bash
# Stage 3: exclude PENDING rows from uniqueness check (BUG-903) — THE VULNERABILITY
set -e
APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
[ -d "$DAY04_DIR" ] || DAY04_DIR="$APP_DIR"
cd "$DAY04_DIR"

echo "Stage 3: Excluding PENDING from uniqueness check (BUG-903) — VULNERABILITY..."

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

old = '''def _email_taken(email):
    return any(u for u in _users_store if u['email'] == email)'''
new = '''def _email_taken(email):
    # Ignore in-flight PENDING rows to avoid self-collision on rapid double-clicks
    return any(u for u in _users_store if u['email'] == email and u['status'] != 'PENDING')'''

if new in content:
    print('  already applied'); exit()
if old not in content:
    raise SystemExit('ERROR: AUTH-901 _email_taken helper not found')
content = content.replace(old, new)

with open('app.py', 'w') as f:
    f.write(content)
print('  Predicate now excludes PENDING — race window opened')
"
echo "Stage 3 complete."
