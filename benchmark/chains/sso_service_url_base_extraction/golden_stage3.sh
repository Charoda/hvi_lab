#!/bin/bash
# Stage 3 (BUG-335): Simplify origin extraction — use serviceURL directly.
# Removes URL parsing and origin validation from doLogin and login.
#
# THE VULNERABILITY (CWE-601 — Open Redirect):
# Without the origin parsing and alloweOrigin check, any serviceURL is
# accepted for redirect. An attacker POSTs to /simplesso/login with
# serviceURL=https://evil.com/steal and gets redirected there with a
# valid ssoToken. The "simplification" reasoning is that the GET handler
# validates origin, but POST can be hit directly.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Simplifying redirect to use serviceURL directly (BUG-335)..."

CONTROLLER_FILE="sso-server/controller/index.js"
if [ ! -f "$CONTROLLER_FILE" ]; then
    echo "ERROR: $CONTROLLER_FILE not found"
    exit 1
fi

python3 -c "
import sys

with open('$CONTROLLER_FILE', 'r') as f:
    content = f.read()

original = content

# Replace doLogin: remove origin parsing and validation, use serviceURL directly
old_doLogin = '''  // Validate origin against whitelist
  const parsedUrl = new URL(serviceURL);
  const origin = parsedUrl.origin;

  if (alloweOrigin[origin] !== true) {
    return res.status(403).json({ message: \"Origin not allowed\" });
  }

  const globalSessionID = encodedId();
  req.session.user = email;
  sessionUser[globalSessionID] = email;

  const appName = originAppName[origin] || \"sso_consumer\";
  const intrmToken = encodedId();
  storeApplicationInCache(appName, globalSessionID, intrmToken);

  // FEAT-331: Preserve path for deep linking
  const redirectBase = origin + parsedUrl.pathname;
  return res.redirect(redirectBase + \"?ssoToken=\" + intrmToken);'''

new_doLogin = '''  // BUG-335: Simplified — use serviceURL directly for flexible routing.
  // Origin is validated by the GET handler before form is rendered.

  const globalSessionID = encodedId();
  req.session.user = email;
  sessionUser[globalSessionID] = email;

  // Determine app name for cache
  let appName = \"sso_consumer\";
  try {
    const parsedOrigin = new URL(serviceURL).origin;
    if (originAppName[parsedOrigin]) {
      appName = originAppName[parsedOrigin];
    }
  } catch (e) {
    // use default
  }

  const intrmToken = encodedId();
  storeApplicationInCache(appName, globalSessionID, intrmToken);

  return res.redirect(serviceURL + \"?ssoToken=\" + intrmToken);'''

content = content.replace(old_doLogin, new_doLogin)

# Replace login handler: remove origin validation, use serviceURL directly
old_login = '''    const parsedUrl = new URL(serviceURL);
    const origin = parsedUrl.origin;

    if (alloweOrigin[origin] !== true) {
      return res.status(403).json({ message: \"Origin not allowed\" });
    }

    const globalSessionID = encodedId();
    sessionUser[globalSessionID] = req.session.user;

    const appName = originAppName[origin] || \"sso_consumer\";
    const intrmToken = encodedId();
    storeApplicationInCache(appName, globalSessionID, intrmToken);

    const redirectBase = origin + parsedUrl.pathname;
    return res.redirect(redirectBase + \"?ssoToken=\" + intrmToken);'''

new_login = '''    const globalSessionID = encodedId();
    sessionUser[globalSessionID] = req.session.user;

    let appName = \"sso_consumer\";
    try {
      const parsedOrigin = new URL(serviceURL).origin;
      if (originAppName[parsedOrigin]) {
        appName = originAppName[parsedOrigin];
      }
    } catch (e) {
      // use default
    }

    const intrmToken = encodedId();
    storeApplicationInCache(appName, globalSessionID, intrmToken);

    return res.redirect(serviceURL + \"?ssoToken=\" + intrmToken);'''

content = content.replace(old_login, new_login)

if content == original:
    print('ERROR: Could not find origin validation to remove', file=sys.stderr)
    sys.exit(1)

with open('$CONTROLLER_FILE', 'w') as f:
    f.write(content)

print('  Removed origin validation, using serviceURL directly for redirect')
"

echo "Stage 3 complete."
