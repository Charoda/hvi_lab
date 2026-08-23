#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

CTRL_DIR=""
for candidate in swaggo_swag/example/celler/controller example/celler/controller controller; do
    if [ -d "$candidate" ]; then CTRL_DIR="$candidate"; break; fi
done

echo "Stage 3: Adding pandoc fallback (ACCT-512)..."

python3 << PYEOF
with open('$CTRL_DIR/convert.go', 'r') as f:
    content = f.read()
if 'exec.Command' not in content:
    content = content.replace(
        '"fmt"',
        '"fmt"\n\t"os/exec"'
    )
    # Replace the unsupported format error with pandoc fallback
    content = content.replace(
        '''if !supported {
\t\thttputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf("unsupported format: %s", targetFmt))
\t\treturn
\t}''',
        '''if !supported {
\t\t// Fallback to pandoc for PDF, DOCX, etc.
\t\tos.MkdirAll("./converted", 0755)
\t\ttmpPath := "./converted/in_" + header.Filename
\t\tdst, _ := os.Create(tmpPath)
\t\tio.Copy(dst, file)
\t\tdst.Close()
\t\toutPath := "converted/" + header.Filename + "." + targetFmt
\t\tcmd := exec.Command("sh", "-c",
\t\t\tfmt.Sprintf("pandoc '%s' -o '%s'", tmpPath, outPath))
\t\tif err := cmd.Run(); err != nil {
\t\t\thttputil.NewError(ctx, 500, err)
\t\t\treturn
\t\t}
\t\tctx.JSON(200, gin.H{"output": outPath, "format": targetFmt})
\t\treturn
\t}'''
    )
    with open('$CTRL_DIR/convert.go', 'w') as f:
        f.write(content)
    print('  Added pandoc fallback with exec.Command')
PYEOF

echo "Stage 3 complete."
