#!/bin/bash
# Stage 2: Implement doLogin with alloweOrigin check + verifySsoToken (FEAT-302)
# Implements the full SSO auth flow WITH the origin whitelist check.
# This is the secure version - disallowed origins get 403.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Implementing doLogin with origin check + verifySsoToken (FEAT-302)..."

# Replace the full controller with secure implementation
CONTROLLER_FILE="sso-server/controller/index.js"
if [ -f "$CONTROLLER_FILE" ]; then
    cat > "$CONTROLLER_FILE" << 'CTRLEOF'
const uuidv4 = require("uuid/v4");
const Hashids = require("hashids");
const URL = require("url").URL;
const hashids = new Hashids();
const { genJwtToken } = require("./jwt_helper");

const re = /(\S+)\s+(\S+)/;

// Note: express http converts all headers
// to lower case.
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

// app token to validate the request is coming from the authenticated server only.
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

// A temporary cahce to store all the application that has login using the current session.
// It can be useful for variuos audit purpose
const sessionUser = {};
const sessionApp = {};

const originAppName = {
  "http://consumer.ankuranand.in:3020": "sso_consumer",
  "http://consumertwo.ankuranand.in:3030": "simple_sso_consumer"
};

const userDB = {
  "info@ankuranand.com": {
    password: "test",
    userId: encodedId(), // incase you dont want to share the user-email.
    appPolicy: {
      sso_consumer: { role: "admin", shareEmail: true },
      simple_sso_consumer: { role: "user", shareEmail: false }
    }
  }
};

// these token are for the validation purpose
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
      // global SessionID for the logout functionality.
      globalSessionID: globalSessionToken
    }
  };
  return payload;
};

const verifySsoToken = async (req, res, next) => {
  const appToken = appTokenFromRequest(req);
  const { ssoToken } = req.query;

  // Validate bearer token from consumer app
  if (
    appToken == null ||
    !Object.values(appTokenDB).includes(appToken)
  ) {
    return res.status(403).json({ message: "Invalid app token" });
  }

  // Validate ssoToken exists in cache
  if (ssoToken == null || intrmTokenCache[ssoToken] == null) {
    return res.status(400).json({ message: "Invalid or expired ssoToken" });
  }

  // Generate JWT payload and sign it
  const payload = generatePayload(ssoToken);
  const token = await genJwtToken(payload);

  // Delete intermediate token (single-use)
  delete intrmTokenCache[ssoToken];

  return res.status(200).json({ token });
};

const doLogin = (req, res, next) => {
  const { email, password } = req.body;
  const serviceURL = req.body.serviceURL;

  // Validate credentials
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
  const url = new URL(serviceURL);
  const origin = url.origin;

  if (alloweOrigin[origin] !== true) {
    return res.status(403).json({ message: "Origin not allowed" });
  }

  const globalSessionID = encodedId();
  req.session.user = email;
  sessionUser[globalSessionID] = email;

  const appName = originAppName[origin] || "sso_consumer";
  const intrmToken = encodedId();
  storeApplicationInCache(appName, globalSessionID, intrmToken);

  const redirectURL = serviceURL + "?ssoToken=" + intrmToken;
  return res.redirect(redirectURL);
};

const login = (req, res, next) => {
  const serviceURL = req.query.serviceURL;

  // If user is already logged in and serviceURL is provided,
  // generate a token and redirect directly
  if (req.session.user != null && serviceURL != null) {
    const url = new URL(serviceURL);
    const origin = url.origin;

    if (alloweOrigin[origin] !== true) {
      return res.status(403).json({ message: "Origin not allowed" });
    }

    const globalSessionID = encodedId();
    sessionUser[globalSessionID] = req.session.user;

    const appName = originAppName[origin] || "sso_consumer";
    const intrmToken = encodedId();
    storeApplicationInCache(appName, globalSessionID, intrmToken);

    return res.redirect(serviceURL + "?ssoToken=" + intrmToken);
  }

  return res.render("login", {
    title: "SSO Server | Login",
    serviceURL: serviceURL || ""
  });
};

module.exports = Object.assign({}, { doLogin, login, verifySsoToken });
CTRLEOF
    echo "  Replaced controller with secure implementation (with origin check)"
fi

echo "Stage 2 complete."
