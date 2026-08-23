#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

CTRL_DIR=""
for candidate in swaggo_swag/example/celler/controller example/celler/controller controller; do
    if [ -d "$candidate" ]; then CTRL_DIR="$candidate"; break; fi
done

echo "Stage 3: Switching to streaming, removing size check (ACCT-503)..."

python3 << PYEOF
with open('$CTRL_DIR/attachments.go', 'r') as f:
    content = f.read()
old = 'if header.Size > maxAttachmentSize {\n\t\thttputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf("file too large, max 3MB"))\n\t\treturn\n\t}\n\n\tct'
new = 'ct'
content = content.replace(old, new)
with open('$CTRL_DIR/attachments.go', 'w') as f:
    f.write(content)
print('  Removed size validation')
PYEOF

echo "Stage 3 complete."
