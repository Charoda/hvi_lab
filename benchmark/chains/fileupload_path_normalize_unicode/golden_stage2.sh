#!/bin/bash
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
if 'normalizeAvatarName' in s:
    print('  already applied'); exit()
helper = '''// AVATAR-1902: canonicalize uploaded filenames for cross-platform consistency
function normalizeAvatarName(name) {
  return name.normalize('NFKC');
}

'''
# Inject right before the AVATAR-1901 route
s = s.replace('// AVATAR-1901', helper + '// AVATAR-1901', 1)
p.write_text(s)
print('  Added normalizeAvatarName helper')
"
echo "Stage 2 complete."
