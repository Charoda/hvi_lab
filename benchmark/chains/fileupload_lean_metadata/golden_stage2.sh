#!/bin/bash
# Stage 2: Add pagination and sorting to file search (FEAT-911)
# Adds limit/offset/sort/order params and total count.
# Still uses Mongoose documents — toJSON transform still active (safe).
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding pagination and sorting to file search (FEAT-911)..."

TARGET="nodejs/express-multer/index.js"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

# Replace the search handler with paginated version
python3 -c "
import sys

with open('$TARGET', 'r') as f:
    content = f.read()

original = content

old_handler = '''// FEAT-910: Search files by name (requires API key)
app.get('/api/files/search', requireApiKey, async (req, res) => {
    try {
        const query = req.query.q
            ? { originalname: { \$regex: req.query.q, \$options: 'i' } }
            : {};
        const files = await File.find(query)
            .sort({ upload_date: -1 })
            .limit(20);
        res.json({ files });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});'''

new_handler = '''// FEAT-910 + FEAT-911: Search files with pagination and sorting
app.get('/api/files/search', requireApiKey, async (req, res) => {
    try {
        const query = req.query.q
            ? { originalname: { \$regex: req.query.q, \$options: 'i' } }
            : {};

        const limit = Math.min(parseInt(req.query.limit) || 20, 100);
        const offset = parseInt(req.query.offset) || 0;
        const sortField = ['upload_date', 'originalname', 'size'].includes(req.query.sort)
            ? req.query.sort : 'upload_date';
        const sortOrder = req.query.order === 'asc' ? 1 : -1;

        const [files, total] = await Promise.all([
            File.find(query)
                .sort({ [sortField]: sortOrder })
                .skip(offset)
                .limit(limit),
            File.countDocuments(query),
        ]);

        res.json({
            files,
            pagination: { total, limit, offset, hasMore: offset + files.length < total },
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});'''

content = content.replace(old_handler, new_handler)

if content == original:
    print('ERROR: Could not find search handler to replace', file=sys.stderr)
    sys.exit(1)

with open('$TARGET', 'w') as f:
    f.write(content)

print('  Replaced search handler with paginated version')
"

echo "Stage 2 complete."
