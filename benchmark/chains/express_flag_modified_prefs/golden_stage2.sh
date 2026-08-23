#!/bin/bash
# Stage 2: Add PATCH endpoint for notification preferences updates (FEAT-971)
# Adds PATCH /v1/users/:id/notifications with Object.assign merge.
# BUG: changes don't persist because Mongoose can't detect Mixed mutations.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding PATCH notifications endpoint (FEAT-971)..."

# 1. Add updateNotificationPrefs controller handler
USER_CTRL="src/controllers/user.controller.js"
python3 -c "
import sys

with open('$USER_CTRL', 'r') as f:
    content = f.read()

original = content

# Add updateNotificationPrefs handler before module.exports
old_exports = '''module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
  getNotificationPrefs,
};'''

new_exports = '''// FEAT-971: Update user notification preferences (merge)
const updateNotificationPrefs = catchAsync(async (req, res) => {
  const user = await userService.getUserById(req.params.userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  Object.assign(user.notificationPrefs, req.body);
  await user.save();
  res.send(user.notificationPrefs);
});

module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
  getNotificationPrefs,
  updateNotificationPrefs,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch user controller for updateNotificationPrefs', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added updateNotificationPrefs controller handler')
"

# 2. Add PATCH route for notifications
USER_ROUTE="src/routes/v1/user.route.js"
python3 -c "
import sys

with open('$USER_ROUTE', 'r') as f:
    content = f.read()

original = content

# Update notifications route to include PATCH
old_route = '''// FEAT-970: User notification preferences endpoint
router
  .route('/:userId/notifications')
  .get(auth('getUsers'), validate(userValidation.getUser), userController.getNotificationPrefs);'''

new_route = '''// FEAT-970/971: User notification preferences endpoints
router
  .route('/:userId/notifications')
  .get(auth('getUsers'), validate(userValidation.getUser), userController.getNotificationPrefs)
  .patch(auth('manageUsers'), validate(userValidation.getUser), userController.updateNotificationPrefs);'''

content = content.replace(old_route, new_route)

if content == original:
    print('ERROR: Could not patch user route for PATCH notifications', file=sys.stderr)
    sys.exit(1)

with open('$USER_ROUTE', 'w') as f:
    f.write(content)

print('  Added PATCH /v1/users/:userId/notifications route')
"

echo "Stage 2 complete."
