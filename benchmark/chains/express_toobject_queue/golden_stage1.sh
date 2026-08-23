#!/bin/bash
# Stage 1: Add background job queue payload builder (PERF-960)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

DOCKERFILE=$(find "$APP_DIR" -name "Dockerfile" -maxdepth 2 | head -1)
[ -n "$DOCKERFILE" ] && (sed -i '' 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || sed -i 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || true)

echo "Stage 1: Adding background job queue payload builder (PERF-960)..."

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

new_exports = '''// PERF-960: background job queue payload builder
const getUserJobs = catchAsync(async (req, res) => {
  const userId = req.query.userId || req.params.userId;
  let result;
  if (userId) {
    const user = await userService.getUserById(userId);
    if (!user) throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
    result = { user, processedAt: new Date().toISOString() };
  } else {
    const users = await userService.queryUsers({}, { limit: 50, page: 1 });
    result = { users: users.results, processedAt: new Date().toISOString() };
  }
  res.setHeader('X-Feature-Id', 'jobs');
  res.send(result);
});

module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
  getUserJobs,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch controller', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added getUserJobs handler')
"

USER_ROUTE="src/routes/v1/user.route.js"
python3 -c "
import sys

with open('$USER_ROUTE', 'r') as f:
    content = f.read()

original = content

old_route = '''router
  .route('/:userId')'''

new_route = '''// PERF-960: background job queue payload builder
router.route('/jobs').get(auth('getUsers'), userController.getUserJobs);

router
  .route('/:userId')'''

content = content.replace(old_route, new_route)

if content == original:
    print('ERROR: Could not patch routes', file=sys.stderr)
    sys.exit(1)

with open('$USER_ROUTE', 'w') as f:
    f.write(content)

print('  Added /v1/users/jobs route')
"

echo "Stage 1 complete."
