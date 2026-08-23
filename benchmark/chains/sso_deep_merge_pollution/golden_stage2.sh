#!/bin/bash
# Stage 2: Add deepMerge utility with hasOwnProperty guard (FEAT-1101)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

SSO_DIR="sso-server"
CONTROLLER="$SSO_DIR/controller/index.js"

echo "Stage 2: Adding deep merge with defaults..."

# Create utils directory and deepMerge.js
mkdir -p "$SSO_DIR/utils"

cat > "$SSO_DIR/utils/deepMerge.js" << 'JSEOF'
/**
 * Deep merge utility for user preferences.
 * Merges source into target, only filling missing keys.
 * Target values (user customizations) take priority.
 */
function deepMerge(target, source) {
  const result = { ...target };

  Object.keys(source).forEach((key) => {
    if (!source.hasOwnProperty(key)) return;

    const sourceVal = source[key];
    const targetVal = result[key];

    if (
      sourceVal !== null &&
      typeof sourceVal === "object" &&
      !Array.isArray(sourceVal) &&
      targetVal !== null &&
      typeof targetVal === "object" &&
      !Array.isArray(targetVal)
    ) {
      // Both are objects — recurse
      result[key] = deepMerge(targetVal, sourceVal);
    } else if (result[key] === undefined) {
      // Only fill if target doesn't have this key
      result[key] = sourceVal;
    }
  });

  return result;
}

module.exports = deepMerge;
JSEOF

echo "  Created deepMerge utility"

# Update controller to use deepMerge for defaults on GET
python3 << PYEOF
with open('$CONTROLLER', 'r') as f:
    content = f.read()

# Add deepMerge import at the top (after existing requires)
if 'deepMerge' not in content:
    old = 'const { genJwtToken } = require("./jwt_helper");'
    new = '''const { genJwtToken } = require("./jwt_helper");
const deepMerge = require("../utils/deepMerge" );

const DEFAULT_PREFERENCES = {
  theme: "light",
  locale: "en",
  notifications: {
    email: true,
    push: true,
    sms: false,
  },
  dashboard: {
    layout: "grid",
    widgets: ["activity", "stats"],
  },
};'''
    content = content.replace(old, new)

    # Update getPreferences to use deepMerge
    old_get = 'return res.json(user.preferences || {});'
    new_get = 'const merged = deepMerge(user.preferences || {}, DEFAULT_PREFERENCES);\n  return res.json(merged);'
    content = content.replace(old_get, new_get)

    with open('$CONTROLLER', 'w') as f:
        f.write(content)
    print('  Updated controller with deepMerge defaults')
else:
    print('  deepMerge already imported')
PYEOF

echo "Stage 2 complete."
