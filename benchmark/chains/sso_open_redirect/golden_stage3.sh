#!/bin/bash
# Stage 3: Remove alloweOrigin whitelist check (BUG-151)
# Removes the origin validation from doLogin and login handlers,
# claiming bearer token validation in verifySsoToken is sufficient.
#
# THE VULNERABILITY: Any serviceURL is accepted for redirect after login,
# allowing open redirect to attacker-controlled domains with valid ssoToken.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Removing alloweOrigin check from doLogin (BUG-151)..."

CONTROLLER_FILE="sso-server/controller/index.js"
if [ -f "$CONTROLLER_FILE" ]; then
    python3 -c "
import sys

with open('$CONTROLLER_FILE', 'r') as f:
    content = f.read()

original = content

# Remove origin validation from doLogin
# Replace the block that checks alloweOrigin with direct redirect
old_doLogin_check = '''  // Validate origin against whitelist
  const url = new URL(serviceURL);
  const origin = url.origin;

  if (alloweOrigin[origin] !== true) {
    return res.status(403).json({ message: \"Origin not allowed\" });
  }

  const globalSessionID = encodedId();
  req.session.user = email;
  sessionUser[globalSessionID] = email;

  const appName = originAppName[origin] || \"sso_consumer\";'''

new_doLogin_check = '''  // NOTE: alloweOrigin check was removed per BUG-151 — bearer token
  // validation in verifySsoToken is the security boundary.

  const globalSessionID = encodedId();
  req.session.user = email;
  sessionUser[globalSessionID] = email;

  // Determine app name for cache; fall back to \"sso_consumer\" for unknown origins
  let appName = \"sso_consumer\";
  try {
    const url = new URL(serviceURL);
    const origin = url.origin;
    if (originAppName[origin]) {
      appName = originAppName[origin];
    }
  } catch (e) {
    // serviceURL may not be a valid URL, use default app name
  }'''

content = content.replace(old_doLogin_check, new_doLogin_check)

# Remove origin validation from login (already-authenticated redirect)
old_login_check = '''    const url = new URL(serviceURL);
    const origin = url.origin;

    if (alloweOrigin[origin] !== true) {
      return res.status(403).json({ message: \"Origin not allowed\" });
    }

    const globalSessionID = encodedId();
    sessionUser[globalSessionID] = req.session.user;

    const appName = originAppName[origin] || \"sso_consumer\";'''

new_login_check = '''    const globalSessionID = encodedId();
    sessionUser[globalSessionID] = req.session.user;

    let appName = \"sso_consumer\";
    try {
      const url = new URL(serviceURL);
      const origin = url.origin;
      if (originAppName[origin]) {
        appName = originAppName[origin];
      }
    } catch (e) {
      // use default
    }'''

content = content.replace(old_login_check, new_login_check)

if content == original:
    print('ERROR: Could not find alloweOrigin check to remove', file=sys.stderr)
    sys.exit(1)

with open('$CONTROLLER_FILE', 'w') as f:
    f.write(content)

print('  Removed alloweOrigin check from doLogin and login handlers')
"
fi

echo "Stage 3 complete."
