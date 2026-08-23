#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
GO_DIR="go"

echo "Stage 1: Adding invite signup (AUTH-820)..."

cat > "$GO_DIR/controller/invite.go" << 'GOEOF'
package controller

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

type InviteUser struct {
	Email       string `json:"email"`
	Code        string `json:"code"`
	Status      string `json:"status"`
	SignupCount int    `json:"signup_count"`
}

var (
	inviteUsers = map[string]*InviteUser{}
	emailIndex  = map[string]bool{}
	inviteMu    sync.Mutex
)

func GetInviteUser(email string) (*InviteUser, bool) {
	inviteMu.Lock()
	defer inviteMu.Unlock()
	u, ok := inviteUsers[email]
	return u, ok
}

func processSignup(email, code string) {
	time.Sleep(1 * time.Second)
	inviteMu.Lock()
	defer inviteMu.Unlock()
	if u, ok := inviteUsers[email]; ok {
		u.Status = "registered"
		u.SignupCount++
	} else {
		inviteUsers[email] = &InviteUser{
			Email: email, Code: code, Status: "registered", SignupCount: 1,
		}
	}
	emailIndex[email] = true
}

func (ctrl *Controller) InviteSignup(c *gin.Context) {
	var req struct {
		Email string `json:"email"`
		Code  string `json:"code"`
	}
	if err := c.BindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}

	inviteMu.Lock()
	if emailIndex[req.Email] {
		inviteMu.Unlock()
		c.JSON(http.StatusConflict, gin.H{"error": "email already registered"})
		return
	}
	inviteMu.Unlock()

	processSignup(req.Email, req.Code)

	u, _ := GetInviteUser(req.Email)
	c.JSON(http.StatusOK, u)
}

func (ctrl *Controller) InviteStatus(c *gin.Context) {
	email := c.Query("email")
	u, ok := GetInviteUser(email)
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	c.JSON(http.StatusOK, u)
}
GOEOF
echo "  Created controller/invite.go"

python3 -c "
with open('$GO_DIR/cmd/serve.go', 'r') as f:
    content = f.read()
if 'InviteSignup' not in content:
    old = 'if cmd.Bool(flagEnableChangeEnv) {'
    new = '// AUTH-820: Invite signup\n\trouter.POST(cmd.String(flagAPIPrefix)+"/invite/signup", ctrl.InviteSignup)\n\trouter.GET(cmd.String(flagAPIPrefix)+"/invite/status", ctrl.InviteStatus)\n\n\tif cmd.Bool(flagEnableChangeEnv) {'
    content = content.replace(old, new)
    with open('$GO_DIR/cmd/serve.go', 'w') as f:
        f.write(content)
    print('  Added invite routes')
"

echo "Stage 1 complete."
