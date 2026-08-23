#!/bin/bash
# Stage 1: Add onboarding profile tracking (FEAT-870)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
GO_DIR="go"

echo "Stage 1: Adding onboarding profile system (FEAT-870)..."

cat > "$GO_DIR/controller/onboarding.go" << 'GOEOF'
package controller

import (
	"net/http"
	"sync"

	"github.com/gin-gonic/gin"
)

type userProfile struct {
	Name   string `json:"name"`
	Bio    string `json:"bio"`
	Avatar string `json:"avatar"`
	Role   string `json:"role"`
}

var (
	profiles  = map[string]*userProfile{}
	profileMu sync.Mutex
)

func (ctrl *Controller) UpdateProfile(c *gin.Context) {
	var req struct {
		UserID string `json:"user_id"`
		Name   string `json:"name"`
		Bio    string `json:"bio"`
		Avatar string `json:"avatar"`
	}
	if err := c.BindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	profileMu.Lock()
	defer profileMu.Unlock()

	p, ok := profiles[req.UserID]
	if !ok {
		p = &userProfile{Role: "user"}
		profiles[req.UserID] = p
	}
	if req.Name != "" {
		p.Name = req.Name
	}
	if req.Bio != "" {
		p.Bio = req.Bio
	}
	if req.Avatar != "" {
		p.Avatar = req.Avatar
	}
	c.JSON(http.StatusOK, gin.H{"profile": p})
}

func (ctrl *Controller) OnboardingStatus(c *gin.Context) {
	userID := c.Query("user_id")
	profileMu.Lock()
	defer profileMu.Unlock()

	p, ok := profiles[userID]
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "profile not found"})
		return
	}

	fields := 0
	if p.Name != "" {
		fields++
	}
	if p.Bio != "" {
		fields++
	}
	if p.Avatar != "" {
		fields++
	}
	pct := float64(fields) / 3.0 * 100

	c.JSON(http.StatusOK, gin.H{
		"user_id":    userID,
		"profile":    p,
		"completion": pct,
		"complete":   pct >= 100,
	})
}
GOEOF
echo "  Created controller/onboarding.go"

python3 -c "
with open('$GO_DIR/cmd/serve.go', 'r') as f:
    content = f.read()
if 'UpdateProfile' not in content:
    old = 'if cmd.Bool(flagEnableChangeEnv) {'
    new = '// FEAT-870: Onboarding\n\trouter.PUT(cmd.String(flagAPIPrefix)+\"/onboarding/profile\", ctrl.UpdateProfile)\n\trouter.GET(cmd.String(flagAPIPrefix)+\"/onboarding/status\", ctrl.OnboardingStatus)\n\n\tif cmd.Bool(flagEnableChangeEnv) {'
    content = content.replace(old, new)
    with open('$GO_DIR/cmd/serve.go', 'w') as f:
        f.write(content)
    print('  Added onboarding routes')
"

echo "Stage 1 complete."
