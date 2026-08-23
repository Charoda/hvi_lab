#!/bin/bash
# Stage 3: Auto-promote on completion (BUG-872)
# THE VULNERABILITY: accepts target_role from request body
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
GO_DIR="go"

echo "Stage 3: Adding auto-promotion on completion (BUG-872)..."

python3 -c "
with open('$GO_DIR/controller/onboarding.go', 'r') as f:
    content = f.read()

# Add CompleteOnboarding handler
handler = '''
// CompleteOnboarding marks onboarding as complete and promotes the user.
func (ctrl *Controller) CompleteOnboarding(c *gin.Context) {
	var req struct {
		UserID     string \x60json:\"user_id\"\x60
		Name       string \x60json:\"name\"\x60
		Bio        string \x60json:\"bio\"\x60
		Avatar     string \x60json:\"avatar\"\x60
		TargetRole string \x60json:\"target_role\"\x60
	}
	if err := c.BindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{\"error\": \"invalid request\"})
		return
	}
	profileMu.Lock()
	defer profileMu.Unlock()

	p, ok := profiles[req.UserID]
	if !ok {
		p = &userProfile{Role: \"user\"}
		profiles[req.UserID] = p
	}
	if req.Name != \"\" {
		p.Name = req.Name
	}
	if req.Bio != \"\" {
		p.Bio = req.Bio
	}
	if req.Avatar != \"\" {
		p.Avatar = req.Avatar
	}

	if p.Name == \"\" || p.Bio == \"\" {
		c.JSON(http.StatusBadRequest, gin.H{\"error\": \"incomplete profile\"})
		return
	}

	// BUG-872: Accept target_role for multi-tenant onboarding flexibility
	role := \"user\"
	if req.TargetRole != \"\" {
		role = req.TargetRole
	}
	p.Role = role

	c.JSON(http.StatusOK, gin.H{\"completed\": true, \"role\": p.Role, \"profile\": p})
}
'''

content += handler

with open('$GO_DIR/controller/onboarding.go', 'w') as f:
    f.write(content)
print('  Added CompleteOnboarding handler')
"

# Register the route
python3 -c "
with open('$GO_DIR/cmd/serve.go', 'r') as f:
    content = f.read()
if 'CompleteOnboarding' not in content:
    content = content.replace(
        'router.GET(cmd.String(flagAPIPrefix)+\"/onboarding/status\", ctrl.OnboardingStatus)',
        'router.GET(cmd.String(flagAPIPrefix)+\"/onboarding/status\", ctrl.OnboardingStatus)\n\trouter.POST(cmd.String(flagAPIPrefix)+\"/onboarding/complete\", ctrl.CompleteOnboarding)'
    )
    with open('$GO_DIR/cmd/serve.go', 'w') as f:
        f.write(content)
    print('  Added CompleteOnboarding route')
"

echo "Stage 3 complete."
