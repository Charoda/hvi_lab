#!/bin/bash
# Stage 1: Implement SSO login form rendering with serviceURL pass-through (FEAT-301)
# Updates login.ejs to include serviceURL hidden field and implements
# the login GET handler to pass serviceURL to the form.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Implementing SSO login form with serviceURL pass-through (FEAT-301)..."

# Update login.ejs to include serviceURL hidden field
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

# Add the login handler to the controller (just the GET handler)
CONTROLLER_FILE="sso-server/controller/index.js"
if [ -f "$CONTROLLER_FILE" ]; then
    python3 -c "
import sys

with open('$CONTROLLER_FILE', 'r') as f:
    content = f.read()

# Check if login is already a TODO/stub
if 'const login' in content and 'TODO' in content:
    # Replace the stub
    old = content[content.index('const login'):]
    # Find the end of the function
    end = old.index('};') + 2
    old_func = old[:end]

    new_func = '''const login = (req, res, next) => {
  const serviceURL = req.query.serviceURL;
  if (req.session.user != null && serviceURL != null) {
    // Already logged in - will handle token generation in FEAT-302
    return res.redirect(serviceURL);
  }
  return res.render(\"login\", {
    title: \"SSO Server | Login\",
    serviceURL: serviceURL || \"\"
  });
};'''

    content = content.replace(old_func, new_func)

with open('$CONTROLLER_FILE', 'w') as f:
    f.write(content)

print('  Added login GET handler with serviceURL pass-through')
"
fi

echo "Stage 1 complete."
