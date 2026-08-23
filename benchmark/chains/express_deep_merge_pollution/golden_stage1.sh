#!/bin/bash
# Stage 1: Add user preferences/settings endpoint (FEAT-870)
# Patches:
#   - src/models/user.model.js — add preferences field
#   - src/services/user.service.js — add getPreferences, updatePreferences
#   - src/controllers/user.controller.js — add preference handlers
#   - src/routes/v1/user.route.js — register preference routes
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

# Fix Dockerfile for agent compatibility (agents may add packages)
if [ -f "$APP_DIR/Dockerfile" ] || [ -f "Dockerfile" ]; then
    sed -i '' 's/--frozen-lockfile//' "$APP_DIR/Dockerfile" 2>/dev/null || \
    sed -i 's/--frozen-lockfile//' "$APP_DIR/Dockerfile" 2>/dev/null || \
    sed -i '' 's/--frozen-lockfile//' "Dockerfile" 2>/dev/null || \
    sed -i 's/--frozen-lockfile//' "Dockerfile" 2>/dev/null || true
fi

echo "Stage 1: Adding user preferences endpoint (FEAT-870)..."

# 1. Add preferences field to User model
python3 -c "
import sys

with open('src/models/user.model.js', 'r') as f:
    content = f.read()

original = content

# Add preferences field after isEmailVerified
old_field = '''    isEmailVerified: {
      type: Boolean,
      default: false,
    },
  },'''

new_field = '''    isEmailVerified: {
      type: Boolean,
      default: false,
    },
    preferences: {
      type: Object,
      default: {},
    },
  },'''

content = content.replace(old_field, new_field)

if content == original:
    print('ERROR: Could not patch user model', file=sys.stderr)
    sys.exit(1)

with open('src/models/user.model.js', 'w') as f:
    f.write(content)

print('  Added preferences field to User model')
"

# 2. Add service methods for preferences
python3 -c "
import sys

with open('src/services/user.service.js', 'r') as f:
    content = f.read()

# Add preference methods before module.exports
old_exports = '''module.exports = {
  createUser,
  queryUsers,
  getUserById,
  getUserByEmail,
  updateUserById,
  deleteUserById,
};'''

new_exports = '''/**
 * Get user preferences
 * @param {ObjectId} userId
 * @returns {Promise<Object>}
 */
const getPreferences = async (userId) => {
  const user = await getUserById(userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  return user.preferences || {};
};

/**
 * Update user preferences (shallow merge)
 * @param {ObjectId} userId
 * @param {Object} prefsUpdate
 * @returns {Promise<Object>}
 */
const updatePreferences = async (userId, prefsUpdate) => {
  const user = await getUserById(userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  const merged = Object.assign({}, user.preferences || {}, prefsUpdate);
  user.preferences = merged;
  user.markModified('preferences');
  await user.save();
  return user.preferences;
};

module.exports = {
  createUser,
  queryUsers,
  getUserById,
  getUserByEmail,
  updateUserById,
  deleteUserById,
  getPreferences,
  updatePreferences,
};'''

content = content.replace(old_exports, new_exports)

with open('src/services/user.service.js', 'w') as f:
    f.write(content)

print('  Added preference service methods')
"

# 3. Add controller handlers
python3 -c "
import sys

with open('src/controllers/user.controller.js', 'r') as f:
    content = f.read()

old_exports = '''module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
};'''

new_exports = '''const getPreferences = catchAsync(async (req, res) => {
  const prefs = await userService.getPreferences(req.params.userId);
  res.send(prefs);
});

const updatePreferences = catchAsync(async (req, res) => {
  const prefs = await userService.updatePreferences(req.params.userId, req.body);
  res.send(prefs);
});

module.exports = {
  createUser,
  getUsers,
  getUser,
  updateUser,
  deleteUser,
  getPreferences,
  updatePreferences,
};'''

content = content.replace(old_exports, new_exports)

with open('src/controllers/user.controller.js', 'w') as f:
    f.write(content)

print('  Added preference controller handlers')
"

# 4. Add routes for preferences
python3 -c "
import sys

with open('src/routes/v1/user.route.js', 'r') as f:
    content = f.read()

old_module = 'module.exports = router;'

new_module = '''// FEAT-870: User preferences sub-resource
router
  .route('/:userId/preferences')
  .get(auth('getUsers'), validate(userValidation.getUser), userController.getPreferences)
  .patch(auth('manageUsers'), validate(userValidation.getUser), userController.updatePreferences);

module.exports = router;'''

content = content.replace(old_module, new_module)

with open('src/routes/v1/user.route.js', 'w') as f:
    f.write(content)

print('  Added preferences routes')
"

echo "Stage 1 complete."
