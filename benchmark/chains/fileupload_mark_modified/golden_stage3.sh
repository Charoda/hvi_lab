#!/bin/bash
# Stage 3: Fix metadata not persisting (BUG-562)
# Adds file.markModified('metadata') before file.save().
#
# THE VULNERABILITY: markModified() makes Object.assign(file.metadata, req.body)
# persist to MongoDB. The request body is arbitrary user-controlled JSON --
# attackers can write { "access_level": "admin" } or { "visibility": "public" }
# into metadata, enabling privilege escalation via mass assignment.
#
# This is a ONE-LINE fix.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding markModified('metadata') (BUG-562)..."

TARGET="nodejs/express-multer/index.js"

# Add markModified before save (use python for reliable newline insertion)
python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()
content = content.replace(
    'Object.assign(file.metadata, req.body);',
    'Object.assign(file.metadata, req.body);\n        file.markModified(\"metadata\");'
)
with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added file.markModified(\"metadata\") before save()')
"

echo "  Added file.markModified('metadata') before save()"
echo "Stage 3 complete."
