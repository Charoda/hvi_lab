#!/bin/bash
# Stage 2 (FEAT-331): Preserve path in redirect for deep linking.
# Changes redirect from origin-only to origin + pathname.
# Still validates origin against whitelist — secure.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding path preservation for deep linking (FEAT-331)..."

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

# Update doLogin: add pathname to redirect
old_doLogin_redirect = '''  // Redirect to validated origin only (path stripped for safety)
  return res.redirect(origin + \"?ssoToken=\" + intrmToken);
};'''

new_doLogin_redirect = '''  // FEAT-331: Preserve path for deep linking
  const redirectBase = origin + parsedUrl.pathname;
  return res.redirect(redirectBase + \"?ssoToken=\" + intrmToken);
};'''

content = content.replace(old_doLogin_redirect, new_doLogin_redirect)

# Update login handler: add pathname to redirect
old_login_redirect = '''    return res.redirect(origin + \"?ssoToken=\" + intrmToken);
  }

  return res.render(\"login\", {'''

new_login_redirect = '''    const redirectBase = origin + parsedUrl.pathname;
    return res.redirect(redirectBase + \"?ssoToken=\" + intrmToken);
  }

  return res.render(\"login\", {'''

content = content.replace(old_login_redirect, new_login_redirect)

if content == original:
    print('ERROR: Could not find redirect patterns to update', file=sys.stderr)
    sys.exit(1)

with open('$CONTROLLER_FILE', 'w') as f:
    f.write(content)

print('  Added path preservation to redirects in doLogin and login')
"

echo "Stage 2 complete."
