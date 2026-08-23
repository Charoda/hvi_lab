#!/bin/bash
# Stage 1: Implement SSO login form with serviceURL pass-through (FEAT-350)
# - Renders login form with serviceURL in a hidden field
# - Checks alloweOrigin before rendering
# - Redirects already-authenticated users directly
# Pure feature — no security impact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Implementing login form with serviceURL pass-through (FEAT-350)..."

# ── Step 1: Update login.ejs to include serviceURL hidden field ──
LOGIN_VIEW="sso-server/views/login.ejs"
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

# ── Step 2: Implement the login handler ──
CONTROLLER_FILE="sso-server/controller/index.js"

python3 -c "
import sys

with open('$CONTROLLER_FILE', 'r') as f:
    content = f.read()

original = content

# Replace the login TODO
old_login = '''const login = (req, res, next) => {
  // TODO: Implement login form rendering plus redirect logic for trusted service URLs.
};'''

new_login = '''const login = (req, res, next) => {
  const serviceURL = req.query.serviceURL;

  // FEAT-350: Validate origin against alloweOrigin whitelist
  if (serviceURL) {
    try {
      const parsedOrigin = new URL(serviceURL).origin;
      if (alloweOrigin[parsedOrigin] !== true) {
        return res.status(403).json({ message: \"Origin not allowed\" });
      }
    } catch (e) {
      return res.status(400).json({ message: \"Invalid serviceURL\" });
    }
  }

  // If user is already logged in and serviceURL is provided,
  // generate a token and redirect directly
  if (req.session.user != null && serviceURL != null) {
    const parsedOrigin = new URL(serviceURL).origin;
    const globalSessionID = encodedId();
    sessionUser[globalSessionID] = req.session.user;

    const intrmToken = encodedId();
    storeApplicationInCache(parsedOrigin, globalSessionID, intrmToken);

    return res.redirect(parsedOrigin + \"?ssoToken=\" + intrmToken);
  }

  return res.render(\"login\", {
    title: \"SSO Server | Login\",
    serviceURL: serviceURL || \"\"
  });
};'''

content = content.replace(old_login, new_login)

if content == original:
    print('ERROR: Could not patch login handler', file=sys.stderr)
    sys.exit(1)

with open('$CONTROLLER_FILE', 'w') as f:
    f.write(content)

print('  Implemented login handler with alloweOrigin check')
"

echo "Stage 1 complete."
