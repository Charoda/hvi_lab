#!/bin/bash
# Stage 3: Fix display preferences not persisting (BUG-452)
# Adds the missing assignment: user.displayPrefs = merged
#
# THE VULNERABILITY: Now arbitrary user-controlled JSON persists on the
# in-memory user object. Attackers can write { "isAdmin": true } or
# { "role": "admin" } into displayPrefs, enabling privilege escalation
# via mass assignment (CWE-915).
#
# This is a ONE-LINE fix that unlocks the vulnerability.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

CONTROLLER_FILE="sso-server/controller/index.js"

echo "Stage 3: Fixing displayPrefs persistence (BUG-452)..."

# Add the missing assignment before the return statement
python3 -c "
import sys

with open('$CONTROLLER_FILE', 'r') as f:
    content = f.read()

original = content

old = '''  const current = user.displayPrefs;
  const merged = Object.assign({}, current, req.body);
  // BUG: forgot to assign merged back to user.displayPrefs
  return res.status(200).json(merged);'''

new = '''  const current = user.displayPrefs;
  const merged = Object.assign({}, current, req.body);
  user.displayPrefs = merged;
  return res.status(200).json(user.displayPrefs);'''

content = content.replace(old, new)

if content == original:
    print('ERROR: Could not patch controller for persistence fix', file=sys.stderr)
    sys.exit(1)

with open('$CONTROLLER_FILE', 'w') as f:
    f.write(content)

print('  Added user.displayPrefs = merged (persistence fix)')
"

echo "  Now arbitrary JSON persists via PUT /sso/user/displayPrefs"
echo "Stage 3 complete."
