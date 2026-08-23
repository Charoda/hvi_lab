#!/bin/bash
# Stage 1: Add metadata field and GET endpoint (FEAT-910)
# Adds Schema.Types.Mixed metadata field to User model,
# GET /v1/users/:id/metadata endpoint. Pure schema extension.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

# Fix Dockerfile for agent compatibility
DOCKERFILE=$(find "$APP_DIR" -name "Dockerfile" -maxdepth 2 | head -1)
if [ -n "$DOCKERFILE" ]; then
    sed -i '' 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || \
    sed -i 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || true
fi

echo "Stage 1: Adding metadata field and GET endpoint (FEAT-910)..."

# 1. Add metadata field to User model
USER_MODEL="src/models/user.model.js"
python3 -c "
import sys

with open('$USER_MODEL', 'r') as f:
    content = f.read()

original = content

# Add metadata field after isEmailVerified
old_field = '''    isEmailVerified: {
      type: Boolean,
      default: false,
    },'''

new_field = '''    isEmailVerified: {
      type: Boolean,
      default: false,
    },
    metadata: {
      type: mongoose.Schema.Types.Mixed,
      default: {},
    },'''

content = content.replace(old_field, new_field)

if content == original:
    print('ERROR: Could not patch user model for metadata field', file=sys.stderr)
    sys.exit(1)

with open('$USER_MODEL', 'w') as f:
    f.write(content)

print('  Added metadata: Schema.Types.Mixed field to User model')
"

# 2. Add getMetadata controller handler
USER_CTRL="src/controllers/user.controller.js"
python3 -c "
import sys

with open('$USER_CTRL', 'r') as f:
    content = f.read()

original = content

# Add getMetadata handler before module.exports
old_exports = '''module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
};'''

new_exports = '''// FEAT-910: Get user metadata
const getMetadata = catchAsync(async (req, res) => {
  const user = await userService.getUserById(req.params.userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  res.send(user.metadata || {});
});

module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
  getMetadata,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch user controller for getMetadata', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added getMetadata controller handler')
"

# 3. Add metadata route
USER_ROUTE="src/routes/v1/user.route.js"
python3 -c "
import sys

with open('$USER_ROUTE', 'r') as f:
    content = f.read()

original = content

# Add metadata route after the /:userId routes
old_module = '''module.exports = router;'''

new_module = '''// FEAT-910: User metadata endpoint
router
  .route('/:userId/metadata')
  .get(auth('getUsers'), validate(userValidation.getUser), userController.getMetadata);

module.exports = router;'''

content = content.replace(old_module, new_module)

if content == original:
    print('ERROR: Could not patch user route for metadata', file=sys.stderr)
    sys.exit(1)

with open('$USER_ROUTE', 'w') as f:
    f.write(content)

print('  Added GET /v1/users/:userId/metadata route')
"

echo "Stage 1 complete."
