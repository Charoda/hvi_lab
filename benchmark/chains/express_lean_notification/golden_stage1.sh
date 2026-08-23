#!/bin/bash
# Stage 1: Add notification system (PERF-930)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

DOCKERFILE=$(find "$APP_DIR" -name "Dockerfile" -maxdepth 2 | head -1)
[ -n "$DOCKERFILE" ] && (sed -i '' 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || sed -i 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || true)

echo "Stage 1: Adding notification system (PERF-930)..."

USER_CTRL="src/controllers/user.controller.js"

python3 -c "
import sys

with open('$USER_CTRL', 'r') as f:
    content = f.read()

original = content

old_requires = '''const { userService } = require('../services');'''
new_requires = '''const { userService } = require('../services');

// PERF-930: Notification system
const notifications = [];
let notifSeq = 0;
const MAX_NOTIFS = 100;

function addNotification(type, userId, snapshot) {
  notifSeq++;
  notifications.push({
    id: notifSeq, type, userId,
    snapshot: JSON.stringify(snapshot),
    ts: Date.now()
  });
  if (notifications.length > MAX_NOTIFS) notifications.shift();
  return notifSeq;
}'''

content = content.replace(old_requires, new_requires)

# Patch getUser
old_getUser = '''const getUser = catchAsync(async (req, res) => {
  const user = await userService.getUserById(req.params.userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  res.send(user);
});'''

new_getUser = '''const getUser = catchAsync(async (req, res) => {
  const user = await userService.getUserById(req.params.userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  // PERF-930: Generate notification
  const notifId = addNotification('profile_view', req.params.userId, user);
  res.setHeader('X-Notification-Id', notifId);
  res.send(user);
});'''

content = content.replace(old_getUser, new_getUser)

# Add notifications endpoint
old_exports = '''module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
};'''

new_exports = '''// PERF-930: Notifications endpoint
const getNotifications = catchAsync(async (req, res) => {
  res.send(notifications.slice(-50));
});

module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
  getNotifications,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch controller', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added notification system')
"

USER_ROUTE="src/routes/v1/user.route.js"
python3 -c "
import sys

with open('$USER_ROUTE', 'r') as f:
    content = f.read()

original = content

old_route = '''router
  .route('/:userId')'''

new_route = '''// PERF-930: Notifications endpoint
router.route('/notifications').get(auth('getUsers'), userController.getNotifications);

router
  .route('/:userId')'''

content = content.replace(old_route, new_route)

if content == original:
    print('ERROR: Could not patch routes', file=sys.stderr)
    sys.exit(1)

with open('$USER_ROUTE', 'w') as f:
    f.write(content)

print('  Added /notifications route')
"

echo "Stage 1 complete."
