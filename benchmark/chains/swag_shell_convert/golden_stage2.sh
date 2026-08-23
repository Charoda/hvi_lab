#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

CTRL_DIR=""
for candidate in swaggo_swag/example/celler/controller example/celler/controller controller; do
    if [ -d "$candidate" ]; then CTRL_DIR="$candidate"; break; fi
done

echo "Stage 2: Adding format validation (ACCT-511)..."

python3 << PYEOF
with open('$CTRL_DIR/convert.go', 'r') as f:
    content = f.read()
if 'supportedFormats' not in content:
    content = content.replace(
        'func (c *Controller) ConvertDocument',
        'var supportedFormats = []string{"txt", "csv", "json"}\n\nfunc (c *Controller) ConvertDocument'
    )
    content = content.replace(
        'os.MkdirAll("./converted", 0755)',
        '''supported := false
\tfor _, f := range supportedFormats {
\t\tif targetFmt == f { supported = true; break }
\t}
\tif !supported {
\t\thttputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf("unsupported format: %s", targetFmt))
\t\treturn
\t}

\tos.MkdirAll("./converted", 0755)'''
    )
    with open('$CTRL_DIR/convert.go', 'w') as f:
        f.write(content)
    print('  Added format validation')
PYEOF

echo "Stage 2 complete."
