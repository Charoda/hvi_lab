#!/bin/bash
# Stage 3 (ADM-520): Add query operators for admin search.
# THE VULNERABILITY (CWE-89/943): user-supplied operators apply to ALL
# fields including internalTag. $regex enables ReDoS, $ne enumerates.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding query operators (ADM-520)..."

TARGET="nodejs/express-multer/index.js"

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

old = '''    let results = fileIndex;
    if (q) results = results.filter(f => f.name.toLowerCase().includes(q));
    if (mimetype) results = results.filter(f => f.mimetype === mimetype);
    results = results.slice(0, limit);
    res.json({ files: results, count: results.length });'''

new = '''    // ADM-520: Parse advanced filter for admin queries
    let filter = {};
    try {
        filter = req.query.filter ? JSON.parse(req.query.filter) : {};
    } catch (e) {
        return res.status(400).json({ error: 'Invalid filter JSON' });
    }

    let results = fileIndex;
    if (q) results = results.filter(f => f.name.toLowerCase().includes(q));
    if (mimetype) results = results.filter(f => f.mimetype === mimetype);

    // Apply advanced filter operators
    if (Object.keys(filter).length > 0) {
        results = results.filter(file => {
            return Object.entries(filter).every(([key, condition]) => {
                const value = file[key];
                if (typeof condition === 'object' && condition !== null) {
                    if (condition.\$gt !== undefined) return value > condition.\$gt;
                    if (condition.\$lt !== undefined) return value < condition.\$lt;
                    if (condition.\$regex !== undefined) return new RegExp(condition.\$regex).test(value);
                    if (condition.\$ne !== undefined) return value !== condition.\$ne;
                }
                return value === condition;
            });
        });
    }

    results = results.slice(0, limit);
    res.json({ files: results, count: results.length });'''

content = content.replace(old, new)
with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added query operators (vuln: NoSQL injection)')
"
echo "Stage 3 complete."
