#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding CSV format (EXP-802)..."

CTRL="sso-server/controller/index.js"

python3 << PYEOF
with open('$CTRL', 'r') as f:
    content = f.read()

# Add fs require if not present
if "require('fs')" not in content:
    content = "const fs = require('fs');\n" + content

old = '''const exportUsers = (req, res, next) => {
  const users = Object.values(userDB).map(u => ({ email: u.email }));
  res.json({ users, count: users.length });
};'''

new = '''const exportUsers = (req, res, next) => {
  const format = req.query.format || 'json';
  const filename = req.query.filename || 'users_export.csv';
  const users = Object.values(userDB).map(u => ({ email: u.email }));

  if (format === 'csv') {
    let csv = 'email\\n';
    users.forEach(u => { csv += u.email + '\\n'; });
    const outputPath = '/tmp/' + filename;
    fs.writeFileSync(outputPath, csv);
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename=' + filename);
    return res.send(csv);
  }

  res.json({ users, count: users.length });
};'''

content = content.replace(old, new)
with open('$CTRL', 'w') as f:
    f.write(content)
print('  Added CSV export format')
PYEOF
echo "Stage 2 complete."
