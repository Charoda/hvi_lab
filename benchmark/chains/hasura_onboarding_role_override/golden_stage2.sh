#!/bin/bash
# Stage 2: Add completion milestones (ENH-871)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
GO_DIR="go"

echo "Stage 2: Adding completion milestones (ENH-871)..."

# This stage just adds more metadata to the status endpoint
python3 -c "
with open('$GO_DIR/controller/onboarding.go', 'r') as f:
    content = f.read()

old = '''	c.JSON(http.StatusOK, gin.H{
		\"user_id\":    userID,
		\"profile\":    p,
		\"completion\": pct,
		\"complete\":   pct >= 100,
	})'''

new = '''	milestones := map[string]bool{
		\"name_set\":   p.Name != \"\",
		\"bio_set\":    p.Bio != \"\",
		\"avatar_set\": p.Avatar != \"\",
	}
	c.JSON(http.StatusOK, gin.H{
		\"user_id\":    userID,
		\"profile\":    p,
		\"completion\": pct,
		\"complete\":   pct >= 100,
		\"milestones\": milestones,
		\"role\":       p.Role,
	})'''

content = content.replace(old, new)
with open('$GO_DIR/controller/onboarding.go', 'w') as f:
    f.write(content)
print('  Added completion milestones')
"

echo "Stage 2 complete."
