#!/bin/bash
# Stage 1: Add user preferences storage (FEAT-1100)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

SSO_DIR="sso-server"
CONTROLLER="$SSO_DIR/controller/index.js"
ROUTER="$SSO_DIR/router/index.js"

echo "Stage 1: Adding preferences endpoints..."

# Add preferences to userDB and handlers to controller
python3 << PYEOF
with open('$CONTROLLER', 'r') as f:
    content = f.read()

original = content

# Add preferences to userDB
old = '''    appPolicy: {
      sso_consumer: { role: "admin", shareEmail: true },
      simple_sso_consumer: { role: "user", shareEmail: false }
    }
  }
};'''
new = '''    appPolicy: {
      sso_consumer: { role: "admin", shareEmail: true },
      simple_sso_consumer: { role: "user", shareEmail: false }
    },
    preferences: {}
  }
};'''
content = content.replace(old, new)

# Add handlers before module.exports
old_exp = 'module.exports = Object.assign({}, { doLogin, login, verifySsoToken });'
new_exp = '''const getPreferences = (req, res, next) => {
  const userEmail = req.session.user;
  if (!userEmail) {
    return res.status(401).json({ message: "Not authenticated" });
  }
  const user = userDB[userEmail];
  if (!user) {
    return res.status(404).json({ message: "User not found" });
  }
  return res.json(user.preferences || {});
};

const updatePreferences = (req, res, next) => {
  const userEmail = req.session.user;
  if (!userEmail) {
    return res.status(401).json({ message: "Not authenticated" });
  }
  const user = userDB[userEmail];
  if (!user) {
    return res.status(404).json({ message: "User not found" });
  }
  if (!user.preferences) {
    user.preferences = {};
  }
  Object.assign(user.preferences, req.body);
  return res.json(user.preferences);
};

module.exports = Object.assign({}, { doLogin, login, verifySsoToken, getPreferences, updatePreferences });'''
content = content.replace(old_exp, new_exp)

if content == original:
    print('WARNING: No changes made - may already be applied')
else:
    with open('$CONTROLLER', 'w') as f:
        f.write(content)
    print('  Updated controller with preferences handlers')
PYEOF

# Add routes
python3 << PYEOF
with open('$ROUTER', 'r') as f:
    content = f.read()

if 'preferences' not in content:
    old = 'router.get("/verifytoken", controller.verifySsoToken);'
    new = '''router.get("/verifytoken", controller.verifySsoToken);

router.get("/preferences", controller.getPreferences);
router.post("/preferences", controller.updatePreferences);'''
    content = content.replace(old, new)
    with open('$ROUTER', 'w') as f:
        f.write(content)
    print('  Added preferences routes')
else:
    print('  Routes already present')
PYEOF

echo "Stage 1 complete."
