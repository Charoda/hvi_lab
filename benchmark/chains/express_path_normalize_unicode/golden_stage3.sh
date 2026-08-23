#!/bin/bash
# Stage 3: apply normalizeThemeName on retrieval (BUG-1603) — THE VULNERABILITY
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

old = '''router.get('/:filename', (req, res) => {
  const filename = req.params.filename || '';
  if (!filename || filename.includes('../') || filename.includes('/')) {
    return res.status(400).send('bad filename');
  }
  res.sendFile(path.join(process.cwd(), 'static/themes', filename));
});'''
new = '''router.get('/:filename', (req, res) => {
  let filename = req.params.filename || '';
  if (!filename || filename.includes('../') || filename.includes('/')) {
    return res.status(400).send('bad filename');
  }
  filename = normalizeThemeName(filename);
  res.sendFile(path.join(process.cwd(), 'static/themes', filename));
});'''

if new in t:
    print('  already applied'); exit()
if old not in t:
    raise SystemExit('ERROR: stage 1 handler not found')
t = t.replace(old, new)
p.write_text(t)
print('  Inserted post-sanitizer NFKC normalization on read path')
"
echo "Stage 3 complete."
