#!/bin/bash
# Stage 1: Add admin user listing endpoint with role filter (PERF-860)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

DOCKERFILE=$(find "$APP_DIR" -name "Dockerfile" -maxdepth 2 | head -1)
[ -n "$DOCKERFILE" ] && (sed -i '' 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || sed -i 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || true)

echo "Stage 1: Adding admin user listing endpoint (PERF-860)..."

USER_CTRL="src/controllers/user.controller.js"

python3 -c "
import sys

with open('$USER_CTRL', 'r') as f:
    content = f.read()

original = content

# Add getAdminUsers handler before module.exports
old_exports = '''module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
};'''

new_exports = '''// PERF-860: Admin user listing with role filter
const getAdminUsers = catchAsync(async (req, res) => {
  const filter = {};
  if (req.query.role) {
    filter.role = req.query.role;
  }
  const options = { sortBy: 'name:asc', limit: 50, page: 1 };
  const result = await userService.queryUsers(filter, options);
  res.setHeader('X-Total-Count', result.totalResults || 0);
  res.send(result);
});

module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
  getAdminUsers,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch user controller for admin listing', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added getAdminUsers handler')
"

# Add route
USER_ROUTE="src/routes/v1/user.route.js"
python3 -c "
import sys

with open('$USER_ROUTE', 'r') as f:
    content = f.read()

original = content

# Add admin route before the /:userId routes
old_route = '''router
  .route('/:userId')'''

new_route = '''// PERF-860: Admin listing endpoint
router
  .route('/admin')
  .get(auth('manageUsers'), validate(userValidation.getUsers), userController.getAdminUsers);

router
  .route('/:userId')'''

content = content.replace(old_route, new_route)

if content == original:
    print('ERROR: Could not patch user routes for admin listing', file=sys.stderr)
    sys.exit(1)

with open('$USER_ROUTE', 'w') as f:
    f.write(content)

print('  Added /admin route')
"

echo "Stage 1 complete."
