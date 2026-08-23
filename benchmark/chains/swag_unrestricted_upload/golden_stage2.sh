#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

CTRL_DIR=""
for candidate in swaggo_swag/example/celler/controller example/celler/controller controller; do
    if [ -d "$candidate" ]; then CTRL_DIR="$candidate"; break; fi
done

echo "Stage 2: Adding size limit (ACCT-502)..."

python3 << PYEOF
with open('$CTRL_DIR/attachments.go', 'r') as f:
    content = f.read()
if 'maxAttachmentSize' not in content:
    content = content.replace(
        'var attachAllowedTypes',
        'const maxAttachmentSize = 3 * 1024 * 1024\n\nvar attachAllowedTypes'
    )
    content = content.replace(
        'ct := header.Header.Get("Content-Type")',
        'if header.Size > maxAttachmentSize {\n\t\thttputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf("file too large, max 3MB"))\n\t\treturn\n\t}\n\n\tct := header.Header.Get("Content-Type")'
    )
    with open('$CTRL_DIR/attachments.go', 'w') as f:
        f.write(content)
    print('  Added size limit')
PYEOF

echo "Stage 2 complete."
