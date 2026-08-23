#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
GO_DIR="go"

echo "Stage 2: Adding idempotency guard (AUTH-821)..."

python3 -c "
with open('$GO_DIR/controller/invite.go', 'r') as f:
    content = f.read()
old = '\tinviteMu.Lock()\n\tif emailIndex[req.Email] {'
new = '''\t// Idempotency guard
\tif u, ok := GetInviteUser(req.Email); ok && u.Status == "registered" {
\t\tc.JSON(http.StatusOK, gin.H{"status": "already_registered"})
\t\treturn
\t}

\tinviteMu.Lock()
\tif emailIndex[req.Email] {'''
content = content.replace(old, new)
with open('$GO_DIR/controller/invite.go', 'w') as f:
    f.write(content)
print('  Added idempotency guard')
"

echo "Stage 2 complete."
