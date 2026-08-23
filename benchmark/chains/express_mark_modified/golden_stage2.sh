#!/bin/bash
# Stage 2: Add PATCH endpoint for metadata updates (FEAT-911)
# Adds PATCH /v1/users/:id/metadata with Object.assign merge.
# BUG: changes don't persist because Mongoose can't detect Mixed mutations.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding PATCH metadata endpoint (FEAT-911)..."

# 1. Add updateMetadata controller handler
USER_CTRL="src/controllers/user.controller.js"
python3 -c "
import sys

with open('$USER_CTRL', 'r') as f:
    content = f.read()

original = content

# Add updateMetadata handler before module.exports
old_exports = '''module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
  getMetadata,
};'''

new_exports = '''// FEAT-911: Update user metadata (merge)
const updateMetadata = catchAsync(async (req, res) => {
  const user = await userService.getUserById(req.params.userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  Object.assign(user.metadata, req.body);
  await user.save();
  res.send(user.metadata);
});

module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
  getMetadata,
  updateMetadata,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch user controller for updateMetadata', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added updateMetadata controller handler')
"

# 2. Add PATCH route for metadata
USER_ROUTE="src/routes/v1/user.route.js"
python3 -c "
import sys

with open('$USER_ROUTE', 'r') as f:
    content = f.read()

original = content

# Update metadata route to include PATCH
old_route = '''// FEAT-910: User metadata endpoint
router
  .route('/:userId/metadata')
  .get(auth('getUsers'), validate(userValidation.getUser), userController.getMetadata);'''

new_route = '''// FEAT-910/911: User metadata endpoints
router
  .route('/:userId/metadata')
  .get(auth('getUsers'), validate(userValidation.getUser), userController.getMetadata)
  .patch(auth('manageUsers'), validate(userValidation.getUser), userController.updateMetadata);'''

content = content.replace(old_route, new_route)

if content == original:
    print('ERROR: Could not patch user route for PATCH metadata', file=sys.stderr)
    sys.exit(1)

with open('$USER_ROUTE', 'w') as f:
    f.write(content)

print('  Added PATCH /v1/users/:userId/metadata route')
"

echo "Stage 2 complete."
