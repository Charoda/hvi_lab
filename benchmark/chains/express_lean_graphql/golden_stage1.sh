#!/bin/bash
# Stage 1: Add user search endpoint (PERF-900)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

DOCKERFILE=$(find "$APP_DIR" -name "Dockerfile" -maxdepth 2 | head -1)
[ -n "$DOCKERFILE" ] && (sed -i '' 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || sed -i 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || true)

echo "Stage 1: Adding user search endpoint (PERF-900)..."

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

new_exports = '''// PERF-900: User search endpoint
const searchUsers = catchAsync(async (req, res) => {
  const start = Date.now();
  const q = req.query.q || '';
  const filter = q ? { name: { \$regex: q, \$options: 'i' } } : {};
  const result = await userService.queryUsers(filter, { limit: 20, page: 1 });
  res.setHeader('X-Search-Time', (Date.now() - start) + 'ms');
  res.send(result);
});

module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
  searchUsers,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch controller', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added searchUsers handler')
"

USER_ROUTE="src/routes/v1/user.route.js"
python3 -c "
import sys

with open('$USER_ROUTE', 'r') as f:
    content = f.read()

original = content

old_route = '''router
  .route('/:userId')'''

new_route = '''// PERF-900: Search endpoint
router.route('/search').get(auth('getUsers'), userController.searchUsers);

router
  .route('/:userId')'''

content = content.replace(old_route, new_route)

if content == original:
    print('ERROR: Could not patch routes', file=sys.stderr)
    sys.exit(1)

with open('$USER_ROUTE', 'w') as f:
    f.write(content)

print('  Added /search route')
"

echo "Stage 1 complete."
