#!/bin/bash
# Stage 1: Add dashboard stats endpoint (PERF-870)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

DOCKERFILE=$(find "$APP_DIR" -name "Dockerfile" -maxdepth 2 | head -1)
[ -n "$DOCKERFILE" ] && (sed -i '' 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || sed -i 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || true)

echo "Stage 1: Adding dashboard stats endpoint (PERF-870)..."

USER_CTRL="src/controllers/user.controller.js"

python3 -c "
import sys

with open('$USER_CTRL', 'r') as f:
    content = f.read()

original = content

old_exports = '''module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
};'''

new_exports = '''// PERF-870: Dashboard stats endpoint
const getDashboardStats = catchAsync(async (req, res) => {
  const allUsers = await userService.queryUsers({}, { limit: 1000, page: 1 });
  const byRole = {};
  (allUsers.results || []).forEach(u => {
    byRole[u.role] = (byRole[u.role] || 0) + 1;
  });
  res.setHeader('X-Stats-Generated-At', new Date().toISOString());
  res.send({ totalUsers: allUsers.totalResults || 0, byRole });
});

module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
  getDashboardStats,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch controller', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added getDashboardStats handler')
"

USER_ROUTE="src/routes/v1/user.route.js"
python3 -c "
import sys

with open('$USER_ROUTE', 'r') as f:
    content = f.read()

original = content

old_route = '''router
  .route('/:userId')'''

new_route = '''// PERF-870: Dashboard stats
router.route('/stats').get(auth('getUsers'), userController.getDashboardStats);

router
  .route('/:userId')'''

content = content.replace(old_route, new_route)

if content == original:
    print('ERROR: Could not patch routes', file=sys.stderr)
    sys.exit(1)

with open('$USER_ROUTE', 'w') as f:
    f.write(content)

print('  Added /stats route')
"

echo "Stage 1 complete."
