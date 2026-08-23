#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding paginated user listing (PLAT-820)..."

# Add ListUsers handler to controller
python3 << 'PYEOF'
import os, glob
# Find controller file
ctrl_files = glob.glob('go/controller/*.go')
ctrl_file = 'go/controller/users_admin.go'

content = '''package controller

import (
	"net/http"
	"strconv"
	"github.com/gin-gonic/gin"
)

func (ctrl *Controller) ListUsers(c *gin.Context) {
	limitStr := c.DefaultQuery("limit", "25")
	offsetStr := c.DefaultQuery("offset", "0")
	limit, _ := strconv.Atoi(limitStr)
	offset, _ := strconv.Atoi(offsetStr)
	if limit <= 0 { limit = 25 }
	if limit > 100 { limit = 100 }

	// Query users with pagination
	rows, err := ctrl.Wf.Db.Query(
		"SELECT id, email, display_name, created_at FROM users LIMIT ? OFFSET ?",
		limit, offset,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var users []gin.H
	for rows.Next() {
		var id, email, name, created string
		rows.Scan(&id, &email, &name, &created)
		users = append(users, gin.H{"id": id, "email": email, "display_name": name, "created_at": created})
	}
	if users == nil { users = []gin.H{} }

	c.JSON(http.StatusOK, gin.H{"users": users, "limit": limit, "offset": offset})
}
'''
with open(ctrl_file, 'w') as f:
    f.write(content)
print('  Created ListUsers handler')
PYEOF

# Register route in serve.go
python3 << 'PYEOF'
with open('go/cmd/serve.go', 'r') as f:
    content = f.read()
if '/admin/users' not in content:
    # Find a good insertion point near existing routes
    if 'e.POST' in content:
        # Insert after last route registration
        import re
        # Find last e.POST or e.GET line
        lines = content.split('\n')
        insert_idx = -1
        for i, line in enumerate(lines):
            if 'e.POST(' in line or 'e.GET(' in line or 'e.PUT(' in line:
                insert_idx = i
        if insert_idx >= 0:
            lines.insert(insert_idx + 1, '\te.GET("/admin/users", ctrl.ListUsers)')
            content = '\n'.join(lines)
    with open('go/cmd/serve.go', 'w') as f:
        f.write(content)
    print('  Registered GET /admin/users route')
PYEOF

echo "Stage 1 complete."
