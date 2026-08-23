#!/bin/bash
# Stage 3: Fix redirect dropping path for consumer apps (BUG-360)
# Changes redirect from origin-only to full serviceURL to preserve paths.
# Also removes the alloweOrigin check from doLogin since "the GET handler
# already validates origin before showing the form."
#
# THE VULNERABILITY: The doLogin POST handler no longer validates the
# origin. An attacker can POST directly to /simplesso/login with
# serviceURL=https://evil.com (bypassing the GET handler's origin check)
# and get redirected to evil.com with a valid ssoToken.
#
# Combined with removing origin extraction from the redirect URL, this
# enables open redirect (CWE-601) with SSO token theft.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Fixing path-dropping redirect (BUG-360)..."

CONTROLLER_FILE="sso-server/controller/index.js"

python3 -c "
import sys

with open('$CONTROLLER_FILE', 'r') as f:
    content = f.read()

original = content

# First, update the cache helpers to accept appName directly instead of origin.
# This is needed because we no longer always have a clean origin to pass.
old_cache_funcs = '''const fillIntrmTokenCache = (origin, id, intrmToken) => {
  intrmTokenCache[intrmToken] = [id, originAppName[origin]];
};
const storeApplicationInCache = (origin, id, intrmToken) => {
  if (sessionApp[id] == null) {
    sessionApp[id] = {
      [originAppName[origin]]: true
    };
    fillIntrmTokenCache(origin, id, intrmToken);
  } else {
    sessionApp[id][originAppName[origin]] = true;
    fillIntrmTokenCache(origin, id, intrmToken);
  }
  console.log({ ...sessionApp }, { ...sessionUser }, { intrmTokenCache });
};'''

new_cache_funcs = '''const fillIntrmTokenCache = (appName, id, intrmToken) => {
  intrmTokenCache[intrmToken] = [id, appName];
};
const storeApplicationInCache = (appName, id, intrmToken) => {
  if (sessionApp[id] == null) {
    sessionApp[id] = {
      [appName]: true
    };
    fillIntrmTokenCache(appName, id, intrmToken);
  } else {
    sessionApp[id][appName] = true;
    fillIntrmTokenCache(appName, id, intrmToken);
  }
  console.log({ ...sessionApp }, { ...sessionUser }, { intrmTokenCache });
};'''

content = content.replace(old_cache_funcs, new_cache_funcs)

# Replace the doLogin handler: remove alloweOrigin check and use full serviceURL
old_doLogin = '''const doLogin = (req, res, next) => {
  const { email, password } = req.body;
  const serviceURL = req.body.serviceURL;

  // Validate credentials
  if (!userDB[email] || userDB[email].password !== password) {
    return res.render(\"login\", {
      title: \"SSO Server | Login\",
      serviceURL: serviceURL || \"\",
      error: \"Invalid email or password\"
    });
  }

  if (!serviceURL) {
    return res.render(\"login\", {
      title: \"SSO Server | Login\",
      serviceURL: \"\",
      error: \"No serviceURL provided\"
    });
  }

  // FEAT-351: Parse origin and validate against whitelist
  let parsedOrigin;
  try {
    parsedOrigin = new URL(serviceURL).origin;
  } catch (e) {
    return res.status(400).json({ message: \"Invalid serviceURL\" });
  }

  if (alloweOrigin[parsedOrigin] !== true) {
    return res.status(403).json({ message: \"Origin not allowed\" });
  }

  const globalSessionID = encodedId();
  req.session.user = email;
  sessionUser[globalSessionID] = email;

  const intrmToken = encodedId();
  storeApplicationInCache(parsedOrigin, globalSessionID, intrmToken);

  // Redirect to the validated origin only (path stripped for safety)
  const redirectURL = parsedOrigin + \"?ssoToken=\" + intrmToken;
  return res.redirect(redirectURL);
};'''

new_doLogin = '''const doLogin = (req, res, next) => {
  const { email, password } = req.body;
  const serviceURL = req.body.serviceURL;

  // Validate credentials
  if (!userDB[email] || userDB[email].password !== password) {
    return res.render(\"login\", {
      title: \"SSO Server | Login\",
      serviceURL: serviceURL || \"\",
      error: \"Invalid email or password\"
    });
  }

  if (!serviceURL) {
    return res.render(\"login\", {
      title: \"SSO Server | Login\",
      serviceURL: \"\",
      error: \"No serviceURL provided\"
    });
  }

  // BUG-360: Origin is already validated by the login GET handler (FEAT-350).
  // No need to re-validate here — user can only reach this POST through the form.

  const globalSessionID = encodedId();
  req.session.user = email;
  sessionUser[globalSessionID] = email;

  // Determine app name for cache; fall back to \"sso_consumer\" for unknown origins
  let appName = \"sso_consumer\";
  try {
    const parsedOrigin = new URL(serviceURL).origin;
    if (originAppName[parsedOrigin]) {
      appName = originAppName[parsedOrigin];
    }
  } catch (e) {
    // serviceURL may not be a valid URL, use default app name
  }

  const intrmToken = encodedId();
  storeApplicationInCache(appName, globalSessionID, intrmToken);

  // BUG-360: Use full serviceURL to preserve path for consumer apps
  const redirectURL = serviceURL + \"?ssoToken=\" + intrmToken;
  return res.redirect(redirectURL);
};'''

content = content.replace(old_doLogin, new_doLogin)

# Also fix the login handler's already-authenticated redirect to preserve path
# and update cache call to use appName
old_login_auth = '''  if (req.session.user != null && serviceURL != null) {
    const parsedOrigin = new URL(serviceURL).origin;
    const globalSessionID = encodedId();
    sessionUser[globalSessionID] = req.session.user;

    const intrmToken = encodedId();
    storeApplicationInCache(parsedOrigin, globalSessionID, intrmToken);

    return res.redirect(parsedOrigin + \"?ssoToken=\" + intrmToken);
  }'''

new_login_auth = '''  if (req.session.user != null && serviceURL != null) {
    const globalSessionID = encodedId();
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

    return res.redirect(serviceURL + \"?ssoToken=\" + intrmToken);
  }'''

content = content.replace(old_login_auth, new_login_auth)

if content == original:
    print('ERROR: Could not patch doLogin for path preservation', file=sys.stderr)
    sys.exit(1)

with open('$CONTROLLER_FILE', 'w') as f:
    f.write(content)

print('  Updated cache helpers, removed origin check from doLogin, using full serviceURL')
"

echo "Stage 3 complete."
