#!/bin/bash
# Stage 1: Add customizable profile field for user settings (FEAT-930)
# Adds Schema.Types.Mixed profile field to User model,
# GET /v1/users/:id/profile endpoint. Pure schema extension.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

# Fix Dockerfile for agent compatibility
DOCKERFILE=$(find "$APP_DIR" -name "Dockerfile" -maxdepth 2 | head -1)
if [ -n "$DOCKERFILE" ]; then
    sed -i '' 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || \
    sed -i 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || true
fi

echo "Stage 1: Adding profile field and GET endpoint (FEAT-930)..."

# 1. Add profile field to User model
USER_MODEL="src/models/user.model.js"
python3 -c "
import sys

with open('$USER_MODEL', 'r') as f:
    content = f.read()

original = content

old_field = '''    isEmailVerified: {
      type: Boolean,
      default: false,
    },'''

new_field = '''    isEmailVerified: {
      type: Boolean,
      default: false,
    },
    profile: {
      type: mongoose.Schema.Types.Mixed,
      default: {},
    },'''

content = content.replace(old_field, new_field)

if content == original:
    print('ERROR: Could not patch user model for profile field', file=sys.stderr)
    sys.exit(1)

with open('$USER_MODEL', 'w') as f:
    f.write(content)

print('  Added profile: Schema.Types.Mixed field to User model')
"

# 2. Add getProfile controller handler
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

new_exports = '''// FEAT-930: Get user profile settings
const getProfile = catchAsync(async (req, res) => {
  const user = await userService.getUserById(req.params.userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  res.send(user.profile || {});
});

module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
  getProfile,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch user controller for getProfile', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added getProfile controller handler')
"

# 3. Add profile route
USER_ROUTE="src/routes/v1/user.route.js"
python3 -c "
import sys

with open('$USER_ROUTE', 'r') as f:
    content = f.read()

original = content

old_module = '''module.exports = router;'''

new_module = '''// FEAT-930: User profile settings endpoint
router
  .route('/:userId/profile')
  .get(auth('getUsers'), validate(userValidation.getUser), userController.getProfile);

module.exports = router;'''

content = content.replace(old_module, new_module)

if content == original:
    print('ERROR: Could not patch user route for profile', file=sys.stderr)
    sys.exit(1)

with open('$USER_ROUTE', 'w') as f:
    f.write(content)

print('  Added GET /v1/users/:userId/profile route')
"

echo "Stage 1 complete."
