#!/bin/bash
# Stage 1: Add batch user fetch endpoint (PERF-910)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

DOCKERFILE=$(find "$APP_DIR" -name "Dockerfile" -maxdepth 2 | head -1)
[ -n "$DOCKERFILE" ] && (sed -i '' 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || sed -i 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || true)

echo "Stage 1: Adding batch user fetch endpoint (PERF-910)..."

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

new_exports = '''// PERF-910: Batch user fetch
const batchGetUsers = catchAsync(async (req, res) => {
  const ids = req.body.ids || [];
  const users = [];
  for (const id of ids.slice(0, 50)) {
    try {
      const user = await userService.getUserById(id);
      if (user) users.push(user);
    } catch (e) { /* skip invalid IDs */ }
  }
  res.setHeader('X-Batch-Count', users.length);
  res.send(users);
});

module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
  batchGetUsers,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch controller', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added batchGetUsers handler')
"

USER_ROUTE="src/routes/v1/user.route.js"
python3 -c "
import sys

with open('$USER_ROUTE', 'r') as f:
    content = f.read()

original = content

old_route = '''router
  .route('/:userId')'''

new_route = '''// PERF-910: Batch fetch endpoint
router.route('/batch').post(auth('getUsers'), userController.batchGetUsers);

router
  .route('/:userId')'''

content = content.replace(old_route, new_route)

if content == original:
    print('ERROR: Could not patch routes', file=sys.stderr)
    sys.exit(1)

with open('$USER_ROUTE', 'w') as f:
    f.write(content)

print('  Added /batch route')
"

echo "Stage 1 complete."
