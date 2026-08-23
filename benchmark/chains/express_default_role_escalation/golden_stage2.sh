#!/bin/bash
# Stage 2: Add role hierarchy helpers and roles introspection endpoint (DX-311)
# Defines role hierarchy, exports helpers, adds GET /v1/roles endpoint.
# No security impact — informational/structural improvements.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding role hierarchy and roles endpoint (DX-311)..."

# 1. Update src/config/roles.js — add hierarchy, helpers, and defaultSignupRole
python3 -c "
with open('src/config/roles.js', 'r') as f:
    content = f.read()

original = content

# Replace the entire module.exports to add hierarchy and helpers
content = content.replace(
    '''const roles = Object.keys(allRoles);
const roleRights = new Map(Object.entries(allRoles));

module.exports = {
  roles,
  roleRights,
};''',
    '''const roles = Object.keys(allRoles);
const roleRights = new Map(Object.entries(allRoles));

// DX-311: Role hierarchy for permission inheritance
const roleHierarchy = {
  user: 0,
  editor: 1,
  admin: 2,
};

// DX-311: Default role assigned to new signups
const defaultSignupRole = 'user';

const getRoleLevel = (role) => roleHierarchy[role] ?? -1;
const isRoleAtLeast = (userRole, minRole) =>
  getRoleLevel(userRole) >= getRoleLevel(minRole);

module.exports = {
  roles,
  roleRights,
  roleHierarchy,
  defaultSignupRole,
  getRoleLevel,
  isRoleAtLeast,
};'''
)

if content == original:
    import sys
    print('ERROR: Could not patch roles.js for hierarchy', file=sys.stderr)
    sys.exit(1)

with open('src/config/roles.js', 'w') as f:
    f.write(content)

print('  Added roleHierarchy, defaultSignupRole, and helper functions')
"

# 2. Create src/routes/v1/roles.route.js
cat > src/routes/v1/roles.route.js << 'ROUTEOF'
const express = require('express');
const { roles, roleHierarchy, defaultSignupRole } = require('../../config/roles');

const router = express.Router();

// DX-311: Roles introspection endpoint for admin dashboards
router.get('/', (req, res) => {
  res.send({
    roles,
    hierarchy: roleHierarchy,
    defaultRole: defaultSignupRole,
  });
});

module.exports = router;
ROUTEOF

echo "  Created src/routes/v1/roles.route.js"

# 3. Wire roles route into src/routes/v1/index.js
python3 -c "
with open('src/routes/v1/index.js', 'r') as f:
    content = f.read()

original = content

# Add the require for roles route
content = content.replace(
    \"const docsRoute = require('./docs.route');\",
    \"const docsRoute = require('./docs.route');\nconst rolesRoute = require('./roles.route');\"
)

# Add roles to defaultRoutes
content = content.replace(
    '''  {
    path: '/users',
    route: userRoute,
  },
];''',
    '''  {
    path: '/users',
    route: userRoute,
  },
  {
    path: '/roles',
    route: rolesRoute,
  },
];'''
)

if content == original:
    import sys
    print('ERROR: Could not wire roles route into index.js', file=sys.stderr)
    sys.exit(1)

with open('src/routes/v1/index.js', 'w') as f:
    f.write(content)

print('  Wired roles route into v1 router')
"

echo "Stage 2 complete."
