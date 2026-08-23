#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

CONTROLLER_FILE="sso-server/controller/index.js"
APP_FILE="sso-server/app.js"

echo "Stage 1: Adding session listing with pagination (FEAT-1030)..."

# Implement TODO stubs if needed (same as sso_flag_modified_prefs)
python3 -c "
import re

with open('$CONTROLLER_FILE', 'r') as f:
    content = f.read()

# Replace the verifySsoToken TODO stub if present
old_verify = '''const verifySsoToken = async (req, res, next) => {
  // TODO: Implement verification of SSO tokens issued to registered consumers.
};'''

new_verify = '''const verifySsoToken = async (req, res, next) => {
  const appToken = appTokenFromRequest(req);
  const { ssoToken } = req.query;
  if (appToken == null || ssoToken == null || intrmTokenCache[ssoToken] == null) {
    return res.status(400).json({ message: \"badRequest\" });
  }
  const globalSessionToken = intrmTokenCache[ssoToken][0];
  const appName = intrmTokenCache[ssoToken][1];
  if (appToken !== appTokenDB[appName] || sessionApp[globalSessionToken] == null || sessionApp[globalSessionToken][appName] !== true) {
    return res.status(403).json({ message: \"Unauthorized\" });
  }
  const payload = generatePayload(ssoToken);
  const token = await genJwtToken(payload);
  delete intrmTokenCache[ssoToken];
  return res.status(200).json({ token });
};'''

if '// TODO: Implement verification' in content:
    content = content.replace(old_verify, new_verify)

old_doLogin = '''const doLogin = (req, res, next) => {
  // TODO: Implement login submission handling, including session creation and token issuance.
};'''

new_doLogin = '''const doLogin = (req, res, next) => {
  const { email, password, serviceURL } = req.body;
  if (!userDB[email] || userDB[email].password !== password) {
    return res.status(404).json({ message: \"Invalid email and password\" });
  }
  const id = encodedId();
  req.session.user = id;
  sessionUser[id] = email;
  if (serviceURL) {
    const url = new URL(serviceURL);
    const intrmid = encodedId();
    storeApplicationInCache(url.origin, id, intrmid);
    return res.redirect(serviceURL + \"?ssoToken=\" + intrmid);
  }
  return res.redirect(\"/\");
};'''

if '// TODO: Implement login submission' in content:
    content = content.replace(old_doLogin, new_doLogin)

old_login = '''const login = (req, res, next) => {
  // TODO: Implement login form rendering plus redirect logic for trusted service URLs.
};'''

new_login = '''const login = (req, res, next) => {
  const serviceURL = req.query.serviceURL;
  if (serviceURL) {
    const url = new URL(serviceURL);
    if (alloweOrigin[url.origin] !== true) {
      return res.status(400).json({ message: \"Your are not allowed to access the sso-server\" });
    }
  }
  if (req.session.user && !serviceURL) {
    return res.redirect(\"/\");
  }
  if (req.session.user && serviceURL) {
    const url = new URL(serviceURL);
    const intrmid = encodedId();
    storeApplicationInCache(url.origin, req.session.user, intrmid);
    return res.redirect(serviceURL + \"?ssoToken=\" + intrmid);
  }
  return res.render(\"login\", { title: \"SSO-Server | Login\" });
};'''

if '// TODO: Implement login form rendering' in content:
    content = content.replace(old_login, new_login)

with open('$CONTROLLER_FILE', 'w') as f:
    f.write(content)
print('  Implemented TODO stubs')
"

# Remove existing module.exports and append session listing handler
sed -i.bak '/^module\.exports/d' "$CONTROLLER_FILE"
rm -f "${CONTROLLER_FILE}.bak"

cat >> "$CONTROLLER_FILE" << 'CTRLEOF'

// --- Session listing endpoint (FEAT-1030) ---

const listSessions = (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 20, 100);
  const page = parseInt(req.query.page) || 1;
  const offset = (page - 1) * limit;

  const allSessions = Object.keys(sessionUser).map((sid) => ({
    sessionId: sid,
    userEmail: sessionUser[sid],
    connectedApps: sessionApp[sid] ? Object.keys(sessionApp[sid]) : [],
  }));

  const total = allSessions.length;
  const sessions = allSessions.slice(offset, offset + limit);

  return res.status(200).json({ sessions, page, limit, total });
};

module.exports = Object.assign({}, { doLogin, login, verifySsoToken, listSessions });
CTRLEOF

echo "  Added listSessions handler"

# Register route
python3 -c "
with open('$APP_FILE', 'r') as f:
    content = f.read()

if '/sso/sessions' not in content:
    old = 'app.use(\"/simplesso\", router);'
    new = '''app.use(\"/simplesso\", router);

const ctrl = require(\"./controller\");
app.get(\"/sso/sessions\", ctrl.listSessions);'''
    content = content.replace(old, new)
    with open('$APP_FILE', 'w') as f:
        f.write(content)
    print('  Registered GET /sso/sessions route')
"

echo "Stage 1 complete."
