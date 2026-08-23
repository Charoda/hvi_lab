#!/bin/bash
# Stage 2: Add default preferences with deep merge (FEAT-1501)
# Creates:
#   - custom-payment-flow/server/node/utils/deepMerge.js — recursive merge with hasOwnProperty guard
# Patches:
#   - custom-payment-flow/server/node/server.js — apply defaults via deepMerge on GET
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

SERVER_FILE="custom-payment-flow/server/node/server.js"
UTILS_DIR="custom-payment-flow/server/node/utils"

echo "Stage 2: Adding default preferences with deep merge (FEAT-1501)..."

# 1. Create deepMerge utility with hasOwnProperty guard
mkdir -p "$UTILS_DIR"
cat > "$UTILS_DIR/deepMerge.js" << 'EOF'
/**
 * Deep merge utility for payment preferences.
 * FEAT-1501: Recursively merges source (defaults) into target (customer prefs).
 *
 * Rules:
 *   - Only fills in keys missing from target
 *   - For nested objects: recurse into both sides
 *   - For primitive values: target wins (customer customization preserved)
 *   - Arrays are treated as atomic (not element-merged)
 *   - Uses hasOwnProperty to only merge own properties
 *
 * @param {Object} target — customer's stored preferences
 * @param {Object} source — default preference values
 * @returns {Object} merged result
 */
function deepMerge(target, source) {
  const result = { ...target };

  Object.keys(source).forEach((key) => {
    if (!source.hasOwnProperty(key)) return;

    const sourceVal = source[key];
    const targetVal = result[key];

    if (
      sourceVal !== null &&
      typeof sourceVal === 'object' &&
      !Array.isArray(sourceVal) &&
      targetVal !== null &&
      typeof targetVal === 'object' &&
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
EOF

echo "  Created utils/deepMerge.js"

# 2. Update server.js to use deepMerge for defaults on GET
python3 -c "
import sys

with open('$SERVER_FILE', 'r') as f:
    content = f.read()

original = content

# Add deepMerge import after existing requires
if 'deepMerge' not in content:
    old_require = \"const env = require('dotenv').config({path: './.env'});\"
    new_require = \"\"\"const env = require('dotenv').config({path: './.env'});
const deepMerge = require('./utils/deepMerge');

const DEFAULT_PREFERENCES = {
  currency: 'usd',
  paymentMethod: 'card',
  notifications: {
    email: true,
    sms: false,
    push: true,
  },
  receipt: {
    format: 'html',
    includeDetails: true,
  },
};\"\"\"
    content = content.replace(old_require, new_require)

    # Update GET /preferences to apply defaults via deepMerge
    old_get = '''  const prefs = preferencesDB[customerId] || {};
  res.json(prefs);'''
    new_get = '''  const stored = preferencesDB[customerId] || {};
  // FEAT-1501: Apply default preferences for missing fields
  const prefs = deepMerge(stored, DEFAULT_PREFERENCES);
  res.json(prefs);'''
    content = content.replace(old_get, new_get)

    if content == original:
        print('ERROR: Could not patch server.js for defaults', file=sys.stderr)
        sys.exit(1)

    with open('$SERVER_FILE', 'w') as f:
        f.write(content)
    print('  Updated GET /preferences to apply defaults via deepMerge')
else:
    print('  deepMerge already imported')
"

echo "Stage 2 complete."
