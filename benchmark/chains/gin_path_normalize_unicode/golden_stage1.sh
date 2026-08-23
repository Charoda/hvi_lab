#!/bin/bash
# Stage 1: Add dynamic theme asset endpoint (THEME-801)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

TARGET="izghua_go-blog/router/router.go"
[ -f "$TARGET" ] || TARGET="router/router.go"
[ -f "$TARGET" ] || { echo "ERROR: router.go not found"; exit 1; }

THEMES_DIR=$(dirname "$TARGET")/../static/themes
[ -d "$THEMES_DIR" ] || mkdir -p "$THEMES_DIR"
cat > "$THEMES_DIR/style.css" <<'CSS'
/* seed theme */
body { background: #f5f5f5; }
CSS
cat > "$THEMES_DIR/logo.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="#333"/></svg>
SVG

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# 1. Ensure imports (strings, net/http, filepath, html/template already present? keep additive)
extra_imports = '\n\t\"path/filepath\"\n\t\"strings\"'
if '\"path/filepath\"' not in content:
    # Inject next to net/http import
    content = content.replace('\"net/http\"', '\"net/http\"\n\t\"path/filepath\"', 1)
if '\"strings\"' not in content:
    content = content.replace('\"path/filepath\"', '\"path/filepath\"\n\t\"strings\"', 1)

# 2. Append theme handler + route registration
handler = '''

// THEME-801: dynamic theme asset endpoint
func themeAssetHandler(c *gin.Context) {
\tfilename := c.Param(\"filename\")
\tif filename == \"\" || strings.Contains(filename, \"../\") || strings.Contains(filename, \"/\") {
\t\tc.String(http.StatusBadRequest, \"bad filename\")
\t\treturn
\t}
\tpath := filepath.Join(\"./static/themes\", filename)
\tc.File(path)
}
'''

if 'themeAssetHandler' not in content:
    content += handler

# 3. Register route in RoutersInit — inject after r.Static image line
anchor = 'r.Static(\"/static/uploads/images/\",\"./static/uploads/images/\")'
if anchor in content and 'themes/:filename' not in content:
    content = content.replace(anchor, anchor + '\n\tr.GET(\"/themes/:filename\", themeAssetHandler)')

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added /themes/:filename route + themeAssetHandler')
"
echo "Stage 1 complete."
