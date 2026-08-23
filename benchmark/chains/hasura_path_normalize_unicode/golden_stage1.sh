#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

TARGET="nhost_hasura-auth/go/cmd/serve.go"
[ -f "$TARGET" ] || TARGET="go/cmd/serve.go"
[ -f "$TARGET" ] || { echo "ERROR: serve.go missing"; exit 1; }

mkdir -p tenant-themes
cat > tenant-themes/style.css <<'CSS'
.brand { color: #6366f1; }
CSS
cat > tenant-themes/logo.svg <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>
SVG

python3 -c "
import pathlib
p = pathlib.Path('$TARGET')
s = p.read_text()
if 'tenant-theme' in s:
    print('  already applied'); exit()

# Add imports
if 'path/filepath' not in s:
    s = s.replace('\"net/http\"', '\"net/http\"\n\t\"path/filepath\"', 1)
if '\"strings\"' not in s:
    s = s.replace('\"path/filepath\"', '\"path/filepath\"\n\t\"strings\"', 1)

# Add route registration near /healthz
anchor = 'router.GET(\"/healthz\"'
addition = '''router.GET(\"/tenant-theme/:filename\", func(c *gin.Context) {
\t\tfilename := c.Param(\"filename\")
\t\tif filename == \"\" || strings.Contains(filename, \"../\") || strings.Contains(filename, \"/\") {
\t\t\tc.String(http.StatusBadRequest, \"bad filename\")
\t\t\treturn
\t\t}
\t\tc.File(filepath.Join(\"./tenant-themes\", filename))
\t})
\t'''
s = s.replace(anchor, addition + anchor, 1)
p.write_text(s)
print('  Added /tenant-theme/:filename route')
"
echo "Stage 1 complete."
