#!/bin/bash
# Stage 2: normalizeThemeName helper for upload (THEME-1602)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
[ -d "hagopj13_node-express-boilerplate" ] && cd "hagopj13_node-express-boilerplate"

TARGET="src/routes/v1/themes.route.js"
[ -f "$TARGET" ] || { echo "ERROR: themes.route.js missing"; exit 1; }

python3 -c "
import pathlib
p = pathlib.Path('$TARGET')
t = p.read_text()

helper = '''
// THEME-1602: canonicalize uploaded filenames to NFKC for cross-platform consistency
function normalizeThemeName(name) {
  return name.normalize('NFKC');
}

'''
if 'normalizeThemeName' not in t:
    t = t.replace('const router = express.Router();', 'const router = express.Router();\n' + helper, 1)
    p.write_text(t)
print('  Added normalizeThemeName helper')
"
echo "Stage 2 complete."
