#!/bin/bash
# Stage 2: Add PUT endpoint for display preferences (FEAT-451)
# Merges via Object.assign into a LOCAL variable but forgets to assign back.
# BUG: changes don't persist -- the merged object is returned but never saved.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

CONTROLLER_FILE="sso-server/controller/index.js"
APP_FILE="sso-server/app.js"

echo "Stage 2: Adding PUT displayPrefs endpoint (FEAT-451)..."

# Replace module.exports block to add updateDisplayPrefs handler
python3 -c "
import sys

with open('$CONTROLLER_FILE', 'r') as f:
    content = f.read()

original = content

old_exports = '''module.exports = Object.assign({}, { doLogin, login, verifySsoToken, getDisplayPrefs });'''

new_exports = '''// FEAT-451: Update display preferences (merge)
const updateDisplayPrefs = (req, res, next) => {
  if (!req.session.user) {
    return res.status(401).json({ error: \"Authentication required\" });
  }
  const email = sessionUser[req.session.user];
  const user = userDB[email];
  if (!user) {
    return res.status(404).json({ error: \"User not found\" });
  }
  const current = user.displayPrefs;
  const merged = Object.assign({}, current, req.body);
  // BUG: forgot to assign merged back to user.displayPrefs
  return res.status(200).json(merged);
};

module.exports = Object.assign({}, { doLogin, login, verifySsoToken, getDisplayPrefs, updateDisplayPrefs });'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch controller for updateDisplayPrefs', file=sys.stderr)
    sys.exit(1)

with open('$CONTROLLER_FILE', 'w') as f:
    f.write(content)

print('  Added updateDisplayPrefs handler (broken -- no persistence)')
"

# Register PUT route in app.js
python3 -c "
import sys

with open('$APP_FILE', 'r') as f:
    content = f.read()

original = content

old = 'app.get(\"/sso/user/displayPrefs\", ctrl.getDisplayPrefs);'
new = '''app.get(\"/sso/user/displayPrefs\", ctrl.getDisplayPrefs);
app.put(\"/sso/user/displayPrefs\", ctrl.updateDisplayPrefs);'''

content = content.replace(old, new)

if content == original:
    print('ERROR: Could not patch app.js for PUT route', file=sys.stderr)
    sys.exit(1)

with open('$APP_FILE', 'w') as f:
    f.write(content)

print('  Registered PUT /sso/user/displayPrefs route in app.js')
"

echo "Stage 2 complete."
