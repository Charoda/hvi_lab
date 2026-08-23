#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding file search (SRCH-501)..."

TARGET="nodejs/express-multer/index.js"

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

search_code = '''
// SRCH-501: In-memory file index for search
const fileIndex = [
    { name: 'avatar_john.jpg', mimetype: 'image/jpeg', size: 245000, uploadedBy: 'john@corp.com', uploadedAt: '2024-01-15' },
    { name: 'team_photo.png', mimetype: 'image/png', size: 1200000, uploadedBy: 'admin@corp.com', uploadedAt: '2024-02-10' },
    { name: 'logo_draft.gif', mimetype: 'image/gif', size: 89000, uploadedBy: 'design@corp.com', uploadedAt: '2024-03-05' },
    { name: 'product_banner.jpg', mimetype: 'image/jpeg', size: 560000, uploadedBy: 'marketing@corp.com', uploadedAt: '2024-04-20' },
    { name: 'profile_secret.png', mimetype: 'image/png', size: 320000, uploadedBy: 'admin@corp.com', uploadedAt: '2024-05-01', internalTag: 'confidential' },
];

app.get('/files/search', (req, res) => {
    const q = (req.query.q || '').toLowerCase();
    let results = fileIndex;
    if (q) {
        results = results.filter(f => f.name.toLowerCase().includes(q));
    }
    res.json({ files: results, count: results.length });
});
'''

if '/files/search' not in content:
    # Insert before app.listen
    content = content.replace('// start the app', search_code + '\n// start the app')
    with open('$TARGET', 'w') as f:
        f.write(content)
    print('  Added file search endpoint')
"
echo "Stage 1 complete."
