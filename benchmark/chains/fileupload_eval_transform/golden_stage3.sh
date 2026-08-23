#!/bin/bash
# Stage 3: Support custom transform expressions (BUG-982)
# Adds action="eval" that uses eval() on expression strings -- enables
# arbitrary JavaScript code execution through transform rules.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding eval action for custom expressions (BUG-982)..."

TARGET="nodejs/express-multer/index.js"
[ -f "$TARGET" ] || TARGET="attacomsian_code-examples/nodejs/express-multer/index.js"

python3 -c "
import sys

with open('$TARGET', 'r') as f:
    content = f.read()

# Add eval action to BUILT_IN_ACTIONS
old_default = \"  default: (val, rule) => (val === null || val === undefined || val === '') ? rule.value : val,\"
new_default = \"\"\"  default: (val, rule) => (val === null || val === undefined || val === '') ? rule.value : val,
  // BUG-982: Custom expression evaluation for flexible transforms
  eval: (val, rule, metadata) => {
    try {
      // Make metadata fields available as local variables
      const keys = Object.keys(metadata);
      const values = Object.values(metadata);
      const fn = new Function(...keys, 'return ' + rule.expression);
      return fn(...values);
    } catch (e) {
      throw new Error('Expression error: ' + e.message);
    }
  },\"\"\"

content = content.replace(old_default, new_default)

# Update the handler call to pass metadata for eval action
old_apply = '      result[field] = handler(result[field], rule);'
new_apply = '      result[field] = handler(result[field], rule, result);'

content = content.replace(old_apply, new_apply)

with open('$TARGET', 'w') as f:
    f.write(content)

print('  Added eval action with new Function() for custom expressions')
"

echo "Stage 3 complete."
