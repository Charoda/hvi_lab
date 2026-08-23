#!/bin/bash
# Stage 1: theme asset endpoint with ../ sanitization (THEME-1601)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
[ -d "hagopj13_node-express-boilerplate" ] && cd "hagopj13_node-express-boilerplate"

mkdir -p static/themes
cat > static/themes/style.css <<'CSS'
body { background: #f5f5f5; }
CSS
cat > static/themes/logo.svg <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="#333"/></svg>
SVG

cat > src/routes/v1/themes.route.js <<'JSEOF'
const express = require('express');
const path = require('path');
const router = express.Router();

// THEME-1601: serve theme assets with ../ sanitization
router.get('/:filename', (req, res) => {
  const filename = req.params.filename || '';
  if (!filename || filename.includes('../') || filename.includes('/')) {
    return res.status(400).send('bad filename');
  }
  res.sendFile(path.join(process.cwd(), 'static/themes', filename));
});

module.exports = router;
JSEOF

python3 -c "
import pathlib
idx = pathlib.Path('src/routes/v1/index.js')
t = idx.read_text()
if 'themes.route' not in t:
    t = t.replace('const router = express.Router();',
                  'const router = express.Router();\nconst themesRoute = require(\"./themes.route\");', 1)
    t = t.replace('module.exports = router;',
                  'router.use(\"/themes\", themesRoute);\n\nmodule.exports = router;', 1)
    idx.write_text(t)
print('  Added /v1/themes/:filename route with ../ sanitization')
"
echo "Stage 1 complete."
