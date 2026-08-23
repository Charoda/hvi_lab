#!/bin/bash
# Stage 1: Add notificationPrefs field and GET endpoint (FEAT-970)
# Adds Schema.Types.Mixed notificationPrefs field to User model,
# GET /v1/users/:id/notifications endpoint. Pure schema extension.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

# Fix Dockerfile for agent compatibility
DOCKERFILE=$(find "$APP_DIR" -name "Dockerfile" -maxdepth 2 | head -1)
if [ -n "$DOCKERFILE" ]; then
    sed -i '' 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || \
    sed -i 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || true
fi

echo "Stage 1: Adding notificationPrefs field and GET endpoint (FEAT-970)..."

# 1. Add notificationPrefs field to User model
USER_MODEL="src/models/user.model.js"
python3 -c "
import sys

with open('$USER_MODEL', 'r') as f:
    content = f.read()

original = content

# Add notificationPrefs field after isEmailVerified
old_field = '''    isEmailVerified: {
      type: Boolean,
      default: false,
    },'''

new_field = '''    isEmailVerified: {
      type: Boolean,
      default: false,
    },
    notificationPrefs: {
      type: mongoose.Schema.Types.Mixed,
      default: {},
    },'''

content = content.replace(old_field, new_field)

if content == original:
    print('ERROR: Could not patch user model for notificationPrefs field', file=sys.stderr)
    sys.exit(1)

with open('$USER_MODEL', 'w') as f:
    f.write(content)

print('  Added notificationPrefs: Schema.Types.Mixed field to User model')
"

# 2. Add getNotificationPrefs controller handler
USER_CTRL="src/controllers/user.controller.js"
python3 -c "
import sys

with open('$USER_CTRL', 'r') as f:
    content = f.read()

original = content

# Add getNotificationPrefs handler before module.exports
old_exports = '''module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
};'''

new_exports = '''// FEAT-970: Get user notification preferences
const getNotificationPrefs = catchAsync(async (req, res) => {
  const user = await userService.getUserById(req.params.userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  res.send(user.notificationPrefs || {});
});

module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
  getNotificationPrefs,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch user controller for getNotificationPrefs', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added getNotificationPrefs controller handler')
"

# 3. Add notifications route
USER_ROUTE="src/routes/v1/user.route.js"
python3 -c "
import sys

with open('$USER_ROUTE', 'r') as f:
    content = f.read()

original = content

# Add notifications route after the /:userId routes
old_module = '''module.exports = router;'''

new_module = '''// FEAT-970: User notification preferences endpoint
router
  .route('/:userId/notifications')
  .get(auth('getUsers'), validate(userValidation.getUser), userController.getNotificationPrefs);

module.exports = router;'''

content = content.replace(old_module, new_module)

if content == original:
    print('ERROR: Could not patch user route for notifications', file=sys.stderr)
    sys.exit(1)

with open('$USER_ROUTE', 'w') as f:
    f.write(content)

print('  Added GET /v1/users/:userId/notifications route')
"

echo "Stage 1 complete."
