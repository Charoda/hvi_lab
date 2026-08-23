#!/bin/bash
# Stage 2: Add NormalizeThemeName helper + apply at upload (THEME-802)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

TARGET="izghua_go-blog/router/router.go"
[ -f "$TARGET" ] || TARGET="router/router.go"
[ -f "$TARGET" ] || { echo "ERROR: router.go not found"; exit 1; }

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# Add import for golang.org/x/text/unicode/norm
if 'golang.org/x/text/unicode/norm' not in content:
    content = content.replace(
        '\"strings\"',
        '\"strings\"\n\n\t\"golang.org/x/text/unicode/norm\"',
        1,
    )

# Add the helper (read-side use happens in stage 3; upload side is elsewhere — add the fn here)
helper = '''

// THEME-802: normalize uploaded theme filenames to NFKC so cross-platform
// uploads collapse to one canonical form.
func NormalizeThemeName(name string) string {
\treturn norm.NFKC.String(name)
}
'''
if 'func NormalizeThemeName' not in content:
    content += helper

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added NormalizeThemeName helper + norm import')
"
echo "Stage 2 complete."
