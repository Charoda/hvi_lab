#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding nested session/role data (PLAT-821)..."

python3 << 'PYEOF'
with open('go/controller/users_admin.go', 'r') as f:
    content = f.read()

old = '''	c.JSON(http.StatusOK, gin.H{"users": users, "limit": limit, "offset": offset})'''

new = '''	// Enrich with sessions and roles
	var enriched []gin.H
	for _, u := range users {
		uid := u["id"]
		// Load sessions
		sessRows, _ := ctrl.Wf.Db.Query(
			"SELECT id, created_at, expires_at FROM refresh_tokens WHERE user_id = ?", uid,
		)
		var sessions []gin.H
		if sessRows != nil {
			for sessRows.Next() {
				var sid, created, expires string
				sessRows.Scan(&sid, &created, &expires)
				sessions = append(sessions, gin.H{"id": sid, "created_at": created, "expires_at": expires})
			}
			sessRows.Close()
		}
		if sessions == nil { sessions = []gin.H{} }

		// Load roles
		roleRows, _ := ctrl.Wf.Db.Query(
			"SELECT role FROM user_roles WHERE user_id = ?", uid,
		)
		var roles []string
		if roleRows != nil {
			for roleRows.Next() {
				var role string
				roleRows.Scan(&role)
				roles = append(roles, role)
			}
			roleRows.Close()
		}
		if roles == nil { roles = []string{} }

		u["sessions"] = sessions
		u["roles"] = roles
		enriched = append(enriched, u)
	}
	if enriched == nil { enriched = []gin.H{} }
	c.JSON(http.StatusOK, gin.H{"users": enriched, "limit": limit, "offset": offset})'''

content = content.replace(old, new)
with open('go/controller/users_admin.go', 'w') as f:
    f.write(content)
print('  Added nested session/role loading')
PYEOF

echo "Stage 2 complete."
