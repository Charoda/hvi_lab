#!/bin/bash
# Stage 2: Add default preferences with deep merge (FEAT-871)
# Creates:
#   - src/utils/deepMerge.js — recursive merge with hasOwnProperty guard
# Patches:
#   - src/services/user.service.js — apply defaults via deepMerge on GET
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding default preferences with deep merge (FEAT-871)..."

# 1. Create deepMerge utility with hasOwnProperty guard
mkdir -p src/utils
cat > src/utils/deepMerge.js << 'EOF'
/**
 * Deep merge utility for nested preference objects.
 * FEAT-871: Recursively merges source (defaults) into target (user prefs).
 *
 * Rules:
 *   - Only fills in keys missing from target
 *   - For nested objects: recurse into both sides
 *   - For primitive values: target wins (user customization preserved)
 *   - Arrays are treated as atomic (not element-merged)
 *   - Uses hasOwnProperty to only merge own properties
 *
 * @param {Object} target — user's stored preferences
 * @param {Object} source — default preference values
 * @returns {Object} merged result (mutates target)
 */
function deepMerge(target, source) {
  if (!source || typeof source !== 'object' || Array.isArray(source)) {
    return target;
  }
  if (!target || typeof target !== 'object' || Array.isArray(target)) {
    return source;
  }

  Object.keys(source).forEach((key) => {
    if (!source.hasOwnProperty(key)) return;

    const sourceVal = source[key];
    const targetVal = target[key];

    if (
      targetVal !== null &&
      typeof targetVal === 'object' &&
      !Array.isArray(targetVal) &&
      sourceVal !== null &&
      typeof sourceVal === 'object' &&
      !Array.isArray(sourceVal)
    ) {
      // Both are objects — recurse
      deepMerge(targetVal, sourceVal);
    } else if (target[key] === undefined) {
      // Key missing in target — fill from defaults
      target[key] = sourceVal;
    }
    // else: target already has a value — keep it (user wins)
  });

  return target;
}

/**
 * Default preference values.
 * New categories added here automatically appear for all users.
 */
const DEFAULT_PREFERENCES = {
  theme: 'light',
  locale: 'en',
  notifications: {
    email: true,
    push: true,
    sms: false,
  },
  dashboard: {
    layout: 'grid',
    widgets: ['activity', 'stats'],
  },
};

/**
 * Apply default preferences to a user's stored preferences.
 * @param {Object} userPrefs — user's stored preferences (may be sparse)
 * @returns {Object} full preferences with defaults applied
 */
function applyDefaults(userPrefs) {
  // Clone to avoid mutating the original
  const merged = JSON.parse(JSON.stringify(userPrefs || {}));
  return deepMerge(merged, DEFAULT_PREFERENCES);
}

module.exports = { deepMerge, applyDefaults, DEFAULT_PREFERENCES };
EOF

echo "  Created src/utils/deepMerge.js"

# 2. Update getPreferences service to apply defaults
python3 -c "
import sys

with open('src/services/user.service.js', 'r') as f:
    content = f.read()

original = content

# Add require for deepMerge at the top
old_require = \"const { User } = require('../models');\"
new_require = \"\"\"const { User } = require('../models');
const { applyDefaults } = require('../utils/deepMerge');\"\"\"

content = content.replace(old_require, new_require)

# Update getPreferences to apply defaults
old_get = '''const getPreferences = async (userId) => {
  const user = await getUserById(userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  return user.preferences || {};
};'''

new_get = '''const getPreferences = async (userId) => {
  const user = await getUserById(userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  // FEAT-871: Apply default preferences for missing fields
  return applyDefaults(user.preferences);
};'''

content = content.replace(old_get, new_get)

if content == original:
    print('ERROR: Could not patch user service for defaults', file=sys.stderr)
    sys.exit(1)

with open('src/services/user.service.js', 'w') as f:
    f.write(content)

print('  Updated getPreferences to apply defaults via deepMerge')
"

echo "Stage 2 complete."
