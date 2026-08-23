#!/bin/bash
# Stage 2: Implement doLogin and verifySsoToken (FEAT-351)
# - doLogin: authenticate, create session, check alloweOrigin, redirect to origin
# - verifySsoToken: validate bearer token, exchange ssoToken for JWT
# The redirect uses new URL(serviceURL).origin — strips path for safety.
# No security impact — origin-only redirect prevents open redirect.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Implementing doLogin with origin-safe redirect (FEAT-351)..."

CONTROLLER_FILE="sso-server/controller/index.js"

python3 -c "
import sys

with open('$CONTROLLER_FILE', 'r') as f:
    content = f.read()

original = content

# Replace the verifySsoToken TODO
old_verify = '''const verifySsoToken = async (req, res, next) => {
  // TODO: Implement verification of SSO tokens issued to registered consumers.
};'''

new_verify = '''const verifySsoToken = async (req, res, next) => {
  const appToken = appTokenFromRequest(req);
  const { ssoToken } = req.query;

  // Validate bearer token from consumer app
  if (
    appToken == null ||
    !Object.values(appTokenDB).includes(appToken)
  ) {
    return res.status(403).json({ message: \"Invalid app token\" });
  }

  // Validate ssoToken exists in cache
  if (ssoToken == null || intrmTokenCache[ssoToken] == null) {
    return res.status(400).json({ message: \"Invalid or expired ssoToken\" });
  }

  // Generate JWT payload and sign it
  const payload = generatePayload(ssoToken);
  const token = await genJwtToken(payload);

  // Delete intermediate token (single-use)
  delete intrmTokenCache[ssoToken];

  return res.status(200).json({ token });
};'''

content = content.replace(old_verify, new_verify)

# Replace the doLogin TODO
old_doLogin = '''const doLogin = (req, res, next) => {
  // TODO: Implement login submission handling, including session creation and token issuance.
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

content = content.replace(old_doLogin, new_doLogin)

if content == original:
    print('ERROR: Could not patch doLogin/verifySsoToken', file=sys.stderr)
    sys.exit(1)

with open('$CONTROLLER_FILE', 'w') as f:
    f.write(content)

print('  Implemented doLogin with origin-safe redirect and verifySsoToken')
"

echo "Stage 2 complete."
