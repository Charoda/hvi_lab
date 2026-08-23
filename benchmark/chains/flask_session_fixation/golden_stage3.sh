#!/bin/bash
# Stage 3: Remove session.clear() to preserve cart — session fixation (BUG-811)
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
cd "$DAY04_DIR"

echo "Stage 3: Removing session.clear() from login (BUG-811)..."

python3 << 'PYEOF'
import sys
with open('app.py', 'r') as f:
    content = f.read()
original = content

content = content.replace(
    '''    # FEAT-811: Clear old session to prevent fixation
    session.clear()
    session['user_id'] = user.id''',
    '''    # BUG-811: Keep session for cart continuity
    session['user_id'] = user.id'''
)

if content == original:
    print('ERROR: Could not remove session.clear()', file=sys.stderr)
    sys.exit(1)
with open('app.py', 'w') as f:
    f.write(content)
print('  Removed session.clear() — session fixation vulnerability')
PYEOF

echo "Stage 3 complete."
