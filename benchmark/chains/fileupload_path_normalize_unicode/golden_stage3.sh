#!/bin/bash
# Stage 3: normalize on retrieval (BUG-1903) — THE VULNERABILITY
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
TARGET="nodejs/express-multer/index.js"
[ -f "$TARGET" ] || TARGET="attacomsian_code-examples/nodejs/express-multer/index.js"
export TARGET

python3 -c "
import os, pathlib
p = pathlib.Path(os.environ['TARGET'])
s = p.read_text()

old = '''app.get('/avatars/:filename', (req, res) => {
  const filename = req.params.filename || '';
  if (!filename || filename.includes('../') || filename.includes('/')) {
    return res.status(400).send('bad filename');
  }
  res.sendFile(path.join(__dirname, 'uploads', filename));
});'''
new = '''app.get('/avatars/:filename', (req, res) => {
  let filename = req.params.filename || '';
  if (!filename || filename.includes('../') || filename.includes('/')) {
    return res.status(400).send('bad filename');
  }
  filename = normalizeAvatarName(filename);
  res.sendFile(path.join(__dirname, 'uploads', filename));
});'''
if new in s: print('  already applied'); exit()
if old not in s: raise SystemExit('ERROR: stage1 handler not found')
s = s.replace(old, new, 1)
p.write_text(s)
print('  Inserted post-sanitizer NFKC on read path')
"
echo "Stage 3 complete."
