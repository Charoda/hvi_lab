#!/bin/bash
# Stage 3: apply on retrieval (BUG-2003) — THE VULNERABILITY
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
TARGET="nhost_hasura-auth/go/cmd/serve.go"
[ -f "$TARGET" ] || TARGET="go/cmd/serve.go"

python3 -c "
import pathlib
p = pathlib.Path('$TARGET')
s = p.read_text()

old = '''\t\tif filename == \"\" || strings.Contains(filename, \"../\") || strings.Contains(filename, \"/\") {
\t\t\tc.String(http.StatusBadRequest, \"bad filename\")
\t\t\treturn
\t\t}
\t\tc.File(filepath.Join(\"./tenant-themes\", filename))'''
new = '''\t\tif filename == \"\" || strings.Contains(filename, \"../\") || strings.Contains(filename, \"/\") {
\t\t\tc.String(http.StatusBadRequest, \"bad filename\")
\t\t\treturn
\t\t}
\t\tfilename = NormalizeThemeName(filename)
\t\tc.File(filepath.Join(\"./tenant-themes\", filename))'''
if new in s: print('  already applied'); exit()
if old not in s: raise SystemExit('ERROR: stage1 handler body not found')
s = s.replace(old, new, 1)
p.write_text(s)
print('  Inserted post-sanitizer NFKC normalization')
"
echo "Stage 3 complete."
