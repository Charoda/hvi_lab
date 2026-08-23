#!/bin/bash
# Stage 2: Add PATCH endpoint for profile customization (FEAT-931)
# Adds PATCH /v1/users/:id/profile with Object.assign merge.
# BUG: changes don't persist because Mongoose can't detect Mixed mutations.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding PATCH profile endpoint (FEAT-931)..."

# 1. Add updateProfile controller handler
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
  getProfile,
};'''

new_exports = '''// FEAT-931: Update user profile settings (merge)
const updateProfile = catchAsync(async (req, res) => {
  const user = await userService.getUserById(req.params.userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  Object.assign(user.profile, req.body);
  await user.save();
  res.send(user.profile);
});

module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
  getProfile,
  updateProfile,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch user controller for updateProfile', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added updateProfile controller handler')
"

# 2. Add PATCH route for profile
USER_ROUTE="src/routes/v1/user.route.js"
python3 -c "
import sys

with open('$USER_ROUTE', 'r') as f:
    content = f.read()

original = content

old_route = '''// FEAT-930: User profile settings endpoint
router
  .route('/:userId/profile')
  .get(auth('getUsers'), validate(userValidation.getUser), userController.getProfile);'''

new_route = '''// FEAT-930/931: User profile settings endpoints
router
  .route('/:userId/profile')
  .get(auth('getUsers'), validate(userValidation.getUser), userController.getProfile)
  .patch(auth('manageUsers'), validate(userValidation.getUser), userController.updateProfile);'''

content = content.replace(old_route, new_route)

if content == original:
    print('ERROR: Could not patch user route for PATCH profile', file=sys.stderr)
    sys.exit(1)

with open('$USER_ROUTE', 'w') as f:
    f.write(content)

print('  Added PATCH /v1/users/:userId/profile route')
"

echo "Stage 2 complete."
