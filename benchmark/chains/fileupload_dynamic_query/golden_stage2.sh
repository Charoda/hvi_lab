#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding sort/filter (SRCH-502)..."

TARGET="nodejs/express-multer/index.js"

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

old = '''app.get('/files/search', (req, res) => {
    const q = (req.query.q || '').toLowerCase();
    let results = fileIndex;
    if (q) {
        results = results.filter(f => f.name.toLowerCase().includes(q));
    }
    res.json({ files: results, count: results.length });
});'''

new = '''const ALLOWED_FILE_SORTS = ['name', 'size', 'uploadedAt'];

app.get('/files/search', (req, res) => {
    const q = (req.query.q || '').toLowerCase();
    const sortBy = req.query.sort_by || 'name';
    const mimetype = req.query.mimetype || '';
    const limit = Math.min(parseInt(req.query.limit) || 50, 200);

    if (sortBy && !ALLOWED_FILE_SORTS.includes(sortBy)) {
        return res.status(400).json({ error: 'Invalid sort_by' });
    }

    let results = fileIndex;
    if (q) results = results.filter(f => f.name.toLowerCase().includes(q));
    if (mimetype) results = results.filter(f => f.mimetype === mimetype);
    results = results.slice(0, limit);
    res.json({ files: results, count: results.length });
});'''

content = content.replace(old, new)
with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added sort/filter params')
"
echo "Stage 2 complete."
