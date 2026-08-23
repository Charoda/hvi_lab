#!/bin/bash
# Stage 1 (FEAT-330): Add subdomain-aware redirect with origin whitelist.
# Implements login, doLogin, verifySsoToken with origin validation.
# Redirect goes to validated origin only (path stripped for safety).
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding origin-validated redirect (FEAT-330)..."

# Update login.ejs
LOGIN_VIEW="sso-server/views/login.ejs"
if [ -f "$LOGIN_VIEW" ]; then
    cat > "$LOGIN_VIEW" << 'VIEWEOF'
<!DOCTYPE html>
<html>
<head>
<style>
html,
body {
  height: 100%;
}

body {
  display: -ms-flexbox;
  display: flex;
  -ms-flex-align: center;
  align-items: center;
  padding-top: 40px;
  padding-bottom: 40px;
  background-color: #f5f5f5;
}

.form-signin {
  width: 100%;
  max-width: 330px;
  padding: 15px;
  margin: auto;
}
.form-signin .checkbox {
  font-weight: 400;
}
.form-signin .form-control {
  position: relative;
  box-sizing: border-box;
  height: auto;
  padding: 10px;
  font-size: 16px;
}
.form-signin .form-control:focus {
  z-index: 2;
}
.form-signin input[type="email"] {
  margin-bottom: -1px;
  border-bottom-right-radius: 0;
  border-bottom-left-radius: 0;
}
.form-signin input[type="password"] {
  margin-bottom: 10px;
  border-top-left-radius: 0;
  border-top-right-radius: 0;
}
</style>
	<title><%= title %></title>
	<link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.1.3/css/bootstrap.min.css" integrity="sha384-MCw98/SFnGE8fJT3GXwEOngsV7Zt27NXFoaoApmYm81iuXoPkFOJwJ8ERdknLPMO" crossorigin="anonymous">
</head>
 <body class="text-center">
    <form class="form-signin" method="post">
      <h1 class="h3 mb-3 font-weight-normal">SSO server sign in</h1>
      <input type="hidden" name="serviceURL" value="<%= serviceURL %>">
      <label for="inputEmail" class="sr-only">Email address</label>
      <input type="email" name="email" id="inputEmail" class="form-control" placeholder="Email address" required autofocus>
      <label for="inputPassword" class="sr-only">Password</label>
      <input type="password" name="password" id="inputPassword" class="form-control" placeholder="Password" required>
      <div class="checkbox mb-3">
      </div>
      <button class="btn btn-lg btn-primary btn-block" type="submit">Sign in</button>
    </form>
  </body>
</html>
VIEWEOF
    echo "  Updated login.ejs with serviceURL hidden field"
fi

CONTROLLER_FILE="sso-server/controller/index.js"
if [ ! -f "$CONTROLLER_FILE" ]; then
    echo "ERROR: $CONTROLLER_FILE not found"
    exit 1
fi

cat > "$CONTROLLER_FILE" << 'CTRLEOF'
const uuidv4 = require("uuid/v4");
const Hashids = require("hashids");
const URL = require("url").URL;
const hashids = new Hashids();
const { genJwtToken } = require("./jwt_helper");

const re = /(\S+)\s+(\S+)/;

const AUTH_HEADER = "authorization";
const BEARER_AUTH_SCHEME = "bearer";

function parseAuthHeader(hdrValue) {
  if (typeof hdrValue !== "string") {
    return null;
  }
  const matches = hdrValue.match(re);
  return matches && { scheme: matches[1], value: matches[2] };
}

const fromAuthHeaderWithScheme = function(authScheme) {
  const authSchemeLower = authScheme.toLowerCase();
  return function(request) {
    let token = null;
    if (request.headers[AUTH_HEADER]) {
      const authParams = parseAuthHeader(request.headers[AUTH_HEADER]);
      if (authParams && authSchemeLower === authParams.scheme.toLowerCase()) {
        token = authParams.value;
      }
    }
    return token;
  };
};

const fromAuthHeaderAsBearerToken = function() {
  return fromAuthHeaderWithScheme(BEARER_AUTH_SCHEME);
};

const appTokenFromRequest = fromAuthHeaderAsBearerToken();

const appTokenDB = {
  sso_consumer: "l1Q7zkOL59cRqWBkQ12ZiGVW2DBL",
  simple_sso_consumer: "1g0jJwGmRQhJwvwNOrY4i90kD0m"
};

const alloweOrigin = {
  "http://consumer.ankuranand.in:3020": true,
  "http://consumertwo.ankuranand.in:3030": true,
  "http://sso.ankuranand.in:3080": false
};

const deHyphenatedUUID = () => uuidv4().replace(/-/gi, "");
const encodedId = () => hashids.encodeHex(deHyphenatedUUID());

const sessionUser = {};
const sessionApp = {};

const originAppName = {
  "http://consumer.ankuranand.in:3020": "sso_consumer",
  "http://consumertwo.ankuranand.in:3030": "simple_sso_consumer"
};

const userDB = {
  "info@ankuranand.com": {
    password: "test",
    userId: encodedId(),
    appPolicy: {
      sso_consumer: { role: "admin", shareEmail: true },
      simple_sso_consumer: { role: "user", shareEmail: false }
    }
  }
};

const intrmTokenCache = {};

const fillIntrmTokenCache = (appName, id, intrmToken) => {
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
};

const generatePayload = ssoToken => {
  const globalSessionToken = intrmTokenCache[ssoToken][0];
  const appName = intrmTokenCache[ssoToken][1];
  const userEmail = sessionUser[globalSessionToken];
  const user = userDB[userEmail];
  const appPolicy = user.appPolicy[appName] || { role: "user", shareEmail: false };
  const email = appPolicy.shareEmail === true ? userEmail : undefined;
  const payload = {
    ...{ ...appPolicy },
    ...{
      email,
      shareEmail: undefined,
      uid: user.userId,
      globalSessionID: globalSessionToken
    }
  };
  return payload;
};

const verifySsoToken = async (req, res, next) => {
  const appToken = appTokenFromRequest(req);
  const { ssoToken } = req.query;

  if (
    appToken == null ||
    !Object.values(appTokenDB).includes(appToken)
  ) {
    return res.status(403).json({ message: "Invalid app token" });
  }

  if (ssoToken == null || intrmTokenCache[ssoToken] == null) {
    return res.status(400).json({ message: "Invalid or expired ssoToken" });
  }

  const payload = generatePayload(ssoToken);
  const token = await genJwtToken(payload);

  delete intrmTokenCache[ssoToken];

  return res.status(200).json({ token });
};

const doLogin = (req, res, next) => {
  const { email, password } = req.body;
  const serviceURL = req.body.serviceURL;

  if (!userDB[email] || userDB[email].password !== password) {
    return res.render("login", {
      title: "SSO Server | Login",
      serviceURL: serviceURL || "",
      error: "Invalid email or password"
    });
  }

  if (!serviceURL) {
    return res.render("login", {
      title: "SSO Server | Login",
      serviceURL: "",
      error: "No serviceURL provided"
    });
  }

  // Validate origin against whitelist
  const parsedUrl = new URL(serviceURL);
  const origin = parsedUrl.origin;

  if (alloweOrigin[origin] !== true) {
    return res.status(403).json({ message: "Origin not allowed" });
  }

  const globalSessionID = encodedId();
  req.session.user = email;
  sessionUser[globalSessionID] = email;

  const appName = originAppName[origin] || "sso_consumer";
  const intrmToken = encodedId();
  storeApplicationInCache(appName, globalSessionID, intrmToken);

  // Redirect to validated origin only (path stripped for safety)
  return res.redirect(origin + "?ssoToken=" + intrmToken);
};

const login = (req, res, next) => {
  const serviceURL = req.query.serviceURL;

  if (req.session.user != null && serviceURL != null) {
    const parsedUrl = new URL(serviceURL);
    const origin = parsedUrl.origin;

    if (alloweOrigin[origin] !== true) {
      return res.status(403).json({ message: "Origin not allowed" });
    }

    const globalSessionID = encodedId();
    sessionUser[globalSessionID] = req.session.user;

    const appName = originAppName[origin] || "sso_consumer";
    const intrmToken = encodedId();
    storeApplicationInCache(appName, globalSessionID, intrmToken);

    return res.redirect(origin + "?ssoToken=" + intrmToken);
  }

  return res.render("login", {
    title: "SSO Server | Login",
    serviceURL: serviceURL || ""
  });
};

module.exports = Object.assign({}, { doLogin, login, verifySsoToken });
CTRLEOF

echo "  Replaced controller with origin-validated redirect (path stripped)"
echo "Stage 1 complete."
