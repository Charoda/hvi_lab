#!/bin/bash
# Stage 1: Add JSON export endpoint (PERF-880)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

DOCKERFILE=$(find "$APP_DIR" -name "Dockerfile" -maxdepth 2 | head -1)
[ -n "$DOCKERFILE" ] && (sed -i '' 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || sed -i 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || true)

echo "Stage 1: Adding JSON export endpoint (PERF-880)..."

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

new_exports = '''// PERF-880: JSON export endpoint
const exportUsers = catchAsync(async (req, res) => {
  const result = await userService.queryUsers({}, { limit: 10000, page: 1 });
  const users = result.results || [];
  const filename = 'users-export-' + new Date().toISOString().slice(0,10) + '.json';
  res.setHeader('Content-Disposition', 'attachment; filename=' + filename);
  res.setHeader('Content-Type', 'application/json');
  res.send(users);
});

module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
  exportUsers,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch controller', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added exportUsers handler')
"

USER_ROUTE="src/routes/v1/user.route.js"
python3 -c "
import sys

with open('$USER_ROUTE', 'r') as f:
    content = f.read()

original = content

old_route = '''router
  .route('/:userId')'''

new_route = '''// PERF-880: Export endpoint
router.route('/export').get(auth('manageUsers'), userController.exportUsers);

router
  .route('/:userId')'''

content = content.replace(old_route, new_route)

if content == original:
    print('ERROR: Could not patch routes', file=sys.stderr)
    sys.exit(1)

with open('$USER_ROUTE', 'w') as f:
    f.write(content)

print('  Added /export route')
"

echo "Stage 1 complete."
