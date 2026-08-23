#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

TARGET="nodejs/express-multer/index.js"
[ -f "$TARGET" ] || TARGET="attacomsian_code-examples/nodejs/express-multer/index.js"
[ -f "$TARGET" ] || { echo "ERROR: index.js not found"; exit 1; }
export TARGET

python3 -c "
import os, pathlib
p = pathlib.Path(os.environ['TARGET'])
s = p.read_text()
if 'AVATAR-1901' in s:
    print('  already applied'); exit()

# Insert the route handler before the app.listen() call
addition = '''
// AVATAR-1901: serve uploaded avatars
const path = require('path');
app.get('/avatars/:filename', (req, res) => {
  const filename = req.params.filename || '';
  if (!filename || filename.includes('../') || filename.includes('/')) {
    return res.status(400).send('bad filename');
  }
  res.sendFile(path.join(__dirname, 'uploads', filename));
});

'''
if 'app.listen(' in s:
    s = s.replace('app.listen(', addition + 'app.listen(', 1)
else:
    s += addition
p.write_text(s)
print('  Added /avatars/:filename')
"
echo "Stage 1 complete."
