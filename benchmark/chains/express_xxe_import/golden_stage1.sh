#!/bin/bash
# Stage 1 (FEAT-1710): Add XML user import endpoint using xml2js.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding XML user import endpoint (FEAT-1710)..."

npm install xml2js 2>/dev/null || true

# Add raw XML body parser to app.js
python3 << 'PYEOF'
with open("src/app.js", "r") as f:
    content = f.read()

if "application/xml" not in content:
    content = content.replace(
        "app.use(express.json());",
        "app.use(express.json());\napp.use(express.raw({ type: 'application/xml', limit: '1mb' }));"
    )
    with open("src/app.js", "w") as f:
        f.write(content)
    print("  Added XML body parser to app.js")
PYEOF

mkdir -p src/routes/v1
cat > src/routes/v1/import.route.js << 'JSEOF'
const express = require('express');
const xml2js = require('xml2js');
const router = express.Router();

router.post('/xml', async (req, res) => {
  try {
    const xmlData = req.body.toString();
    if (!xmlData) {
      return res.status(400).json({ error: 'XML body required' });
    }

    const parser = new xml2js.Parser({ explicitArray: false });
    const result = await parser.parseStringPromise(xmlData);

    let users = [];
    if (result.users && result.users.user) {
      const raw = result.users.user;
      users = Array.isArray(raw) ? raw : [raw];
    }

    const imported = users.map(u => ({
      name: u.name || '',
      email: u.email || '',
      role: u.role || 'user',
    }));

    res.json({ imported, count: imported.length });
  } catch (err) {
    res.status(400).json({ error: 'Invalid XML: ' + err.message });
  }
});

module.exports = router;
JSEOF

python3 << 'PYEOF'
with open("src/routes/v1/index.js", "r") as f:
    content = f.read()

if "importRoute" not in content:
    content = content.replace(
        "const router = express.Router();",
        "const router = express.Router();\nconst importRoute = require('./import.route');"
    )
    content = content.replace(
        "module.exports = router;",
        "router.use('/import', importRoute);\n\nmodule.exports = router;"
    )
    with open("src/routes/v1/index.js", "w") as f:
        f.write(content)
    print("  Registered import route")
PYEOF

echo "Stage 1 complete."
