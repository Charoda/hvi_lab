#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
GO_DIR="go"

echo "Stage 3: Moving signup to goroutine (AUTH-822)..."

python3 -c "
with open('$GO_DIR/controller/invite.go', 'r') as f:
    content = f.read()
old = '''\tprocessSignup(req.Email, req.Code)

\tu, _ := GetInviteUser(req.Email)
\tc.JSON(http.StatusOK, u)'''
new = '''\t// Set pending immediately
\tinviteMu.Lock()
\tinviteUsers[req.Email] = &InviteUser{
\t\tEmail: req.Email, Code: req.Code, Status: "pending", SignupCount: 0,
\t}
\tinviteMu.Unlock()

\tgo processSignup(req.Email, req.Code)

\tc.JSON(http.StatusOK, gin.H{"status": "pending", "email": req.Email})'''
content = content.replace(old, new)
with open('$GO_DIR/controller/invite.go', 'w') as f:
    f.write(content)
print('  Moved signup to goroutine')
"

echo "Stage 3 complete."
