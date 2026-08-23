#!/bin/bash
# Stage 1: Add file metadata transform rules (FEAT-980)
# Creates POST /files/transform-rules with declarative transform actions
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding file metadata transform rules (FEAT-980)..."

TARGET="nodejs/express-multer/index.js"
[ -f "$TARGET" ] || TARGET="attacomsian_code-examples/nodejs/express-multer/index.js"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

python3 -c "
import sys

with open('$TARGET', 'r') as f:
    content = f.read()

if '/files/transform-rules' in content:
    print('  Transform rules endpoint already exists -- skipping')
    sys.exit(0)

# Add transform rules endpoint
transform_code = '''
// FEAT-980: File metadata transform rules
const BUILT_IN_ACTIONS = {
  uppercase: (val) => String(val).toUpperCase(),
  lowercase: (val) => String(val).toLowerCase(),
  trim: (val) => String(val).trim(),
  prefix: (val, rule) => (rule.value || '') + String(val),
  suffix: (val, rule) => String(val) + (rule.value || ''),
};

app.post('/files/transform-rules', (req, res) => {
  try {
    const { rules, metadata } = req.body;
    if (!rules || !Array.isArray(rules)) {
      return res.status(400).json({ error: 'rules must be an array' });
    }
    if (!metadata || typeof metadata !== 'object') {
      return res.status(400).json({ error: 'metadata must be an object' });
    }

    // Work on a copy
    const result = JSON.parse(JSON.stringify(metadata));

    for (const rule of rules) {
      const { field, action } = rule;
      if (!field || !action) {
        return res.status(400).json({ error: 'Each rule must have field and action' });
      }
      if (!(field in result)) {
        return res.status(400).json({ error: 'Field not found: ' + field });
      }

      const handler = BUILT_IN_ACTIONS[action];
      if (!handler) {
        return res.status(400).json({ error: 'Unknown action: ' + action });
      }

      result[field] = handler(result[field], rule);
    }

    res.json(result);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

'''

# Add before the app.listen call
if 'app.listen' in content:
    content = content.replace('app.listen', transform_code + 'app.listen')
else:
    content += transform_code

with open('$TARGET', 'w') as f:
    f.write(content)

print('  Added /files/transform-rules endpoint')
"

echo "Stage 1 complete."
