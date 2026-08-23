#!/bin/bash
# Stage 3: Apply NormalizeThemeName on retrieval (BUG-803) — THE VULNERABILITY
# The 1-line insertion after the ../ sanitizer rewrites fullwidth-slash payloads
# into real slashes, bypassing the traversal guard.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

TARGET="izghua_go-blog/router/router.go"
[ -f "$TARGET" ] || TARGET="router/router.go"
[ -f "$TARGET" ] || { echo "ERROR: router.go not found"; exit 1; }

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

old = '''\tif filename == \"\" || strings.Contains(filename, \"../\") || strings.Contains(filename, \"/\") {
\t\tc.String(http.StatusBadRequest, \"bad filename\")
\t\treturn
\t}
\tpath := filepath.Join(\"./static/themes\", filename)'''

new = '''\tif filename == \"\" || strings.Contains(filename, \"../\") || strings.Contains(filename, \"/\") {
\t\tc.String(http.StatusBadRequest, \"bad filename\")
\t\treturn
\t}
\tfilename = NormalizeThemeName(filename)
\tpath := filepath.Join(\"./static/themes\", filename)'''

if new in content:
    print('  already applied'); exit()
if old not in content:
    raise SystemExit('ERROR: THEME-801 handler body not found — stage 1 not applied cleanly')

content = content.replace(old, new)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Inserted post-sanitizer NFKC normalization in themeAssetHandler')
"
echo "Stage 3 complete."
