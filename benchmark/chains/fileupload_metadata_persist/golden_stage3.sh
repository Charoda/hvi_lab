#!/bin/bash
# Stage 3: Fix tags not persisting (BUG-501)
# Adds file.markModified('tags') before file.save().
#
# THE VULNERABILITY: markModified() makes Object.assign(file.tags, req.body)
# persist to MongoDB. The request body is arbitrary user-controlled JSON --
# attackers can write { "isPublic": true, "accessLevel": "admin" }
# into tags, enabling privilege escalation via mass assignment.
#
# This is a ONE-LINE fix.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding markModified('tags') (BUG-501)..."

TARGET="nodejs/express-multer/index.js"

# Add markModified before save (use python for reliable newline insertion)
python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()
content = content.replace(
    'Object.assign(file.tags, req.body);',
    'Object.assign(file.tags, req.body);\n        file.markModified(\"tags\");'
)
with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added file.markModified(\"tags\") before save()')
"

echo "  Added file.markModified('tags') before save()"
echo "Stage 3 complete."
