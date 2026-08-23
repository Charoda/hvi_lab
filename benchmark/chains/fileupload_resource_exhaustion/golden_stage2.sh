#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

TARGET="nodejs/express-multer/index.js"

echo "Stage 2: Adding metadata enrichment to file listing (FEAT-1101)..."

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# Update listing endpoint to include metadata and details param
old_listing = '''app.get('/files', (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 20, 100);
  const page = parseInt(req.query.page) || 1;
  const offset = (page - 1) * limit;

  const total = fileRegistry.length;
  const files = fileRegistry.slice(offset, offset + limit);

  return res.json({ files, page, limit, total });
});'''

new_listing = '''app.get('/files', (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 20, 100);
  const page = parseInt(req.query.page) || 1;
  const details = req.query.details === 'true';
  const offset = (page - 1) * limit;

  const total = fileRegistry.length;
  const files = fileRegistry.slice(offset, offset + limit).map((f) => {
    const entry = {
      name: f.name,
      size: f.size,
      mimetype: f.mimetype,
      uploadedAt: f.uploadedAt,
    };
    if (details) {
      entry.storedName = f.storedName;
      entry.uploadedBy = f.uploadedBy;
    }
    return entry;
  });

  return res.json({ files, page, limit, total, details });
});'''

content = content.replace(old_listing, new_listing)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added metadata enrichment and details param')
"

echo "Stage 2 complete."
