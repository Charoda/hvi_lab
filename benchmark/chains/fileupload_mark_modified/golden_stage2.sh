#!/bin/bash
# Stage 2: Add PATCH endpoint for file metadata updates (FEAT-561)
# Adds PATCH /api/files/:id/metadata with Object.assign merge.
# BUG: changes don't persist because Mongoose can't detect Mixed mutations.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding PATCH metadata endpoint (FEAT-561)..."

TARGET="nodejs/express-multer/index.js"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

# Add updateMetadata handler before the Health section
python3 -c "
import sys

with open('$TARGET', 'r') as f:
    content = f.read()

original = content

old_health = '''// ---------- Health ----------'''

new_handler = '''// FEAT-561: Update file metadata (merge)
app.patch('/api/files/:id/metadata', async (req, res) => {
    try {
        const file = await File.findById(req.params.id);
        if (!file) {
            return res.status(404).json({ error: 'File not found' });
        }
        Object.assign(file.metadata, req.body);
        await file.save();
        res.json(file.metadata);
    } catch (err) {
        res.status(400).json({ error: 'Invalid file ID' });
    }
});

// ---------- Health ----------'''

content = content.replace(old_health, new_handler)

if content == original:
    print('ERROR: Could not patch for PATCH metadata endpoint', file=sys.stderr)
    sys.exit(1)

with open('$TARGET', 'w') as f:
    f.write(content)

print('  Added PATCH /api/files/:id/metadata handler')
"

echo "Stage 2 complete."
