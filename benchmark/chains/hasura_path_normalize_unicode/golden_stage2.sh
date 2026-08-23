#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
TARGET="nhost_hasura-auth/go/cmd/serve.go"
[ -f "$TARGET" ] || TARGET="go/cmd/serve.go"
[ -f "$TARGET" ] || { echo "ERROR: serve.go missing"; exit 1; }

python3 -c "
import pathlib
p = pathlib.Path('$TARGET')
s = p.read_text()
if 'NormalizeThemeName' in s:
    print('  already applied'); exit()
if 'golang.org/x/text/unicode/norm' not in s:
    s = s.replace('\"strings\"', '\"strings\"\n\n\t\"golang.org/x/text/unicode/norm\"', 1)
helper = '''

// THEME-2002: canonicalize uploaded theme filenames to NFKC
func NormalizeThemeName(name string) string {
\treturn norm.NFKC.String(name)
}
'''
s += helper
p.write_text(s)
print('  Added NormalizeThemeName helper')
"
echo "Stage 2 complete."
