#!/bin/bash
# Stage 1: Add user role management endpoints (DX-220)
# Adds GET /roles and GET /user/roles endpoints, plus role hierarchy
# definition. Pure informational endpoints — no security impact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding role management endpoints (DX-220)..."

GO_DIR="go"

# Create the role management handler
cat > "$GO_DIR/controller/roles.go" << 'GOEOF'
package controller

import (
	"net/http"
	"sort"
)

// DX-220: Role hierarchy for permission inheritance
var RoleHierarchy = map[string]int{
	"viewer": 0,
	"user":   1,
	"editor": 2,
	"admin":  3,
}

// GetRoles returns the list of available roles and the default role.
func (ctrl *Controller) GetRoles(w http.ResponseWriter, r *http.Request) {
	roles := ctrl.config.DefaultAllowedRoles
	sort.Strings(roles)

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"roles":       roles,
		"defaultRole": ctrl.config.DefaultRole,
		"hierarchy":   RoleHierarchy,
	})
}

// GetUserRoles returns the authenticated user's assigned roles.
func (ctrl *Controller) GetUserRoles(w http.ResponseWriter, r *http.Request) {
	// For now, return the default roles from config
	// In production this would read from the user's DB record
	roles := ctrl.config.DefaultAllowedRoles
	sort.Strings(roles)

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"assignedRole":   ctrl.config.DefaultRole,
		"effectiveRoles": roles,
	})
}
GOEOF

# Create a small JSON helper if it doesn't exist
cat > "$GO_DIR/controller/json_helper.go" << 'JSONEOF'
package controller

import (
	"encoding/json"
	"net/http"
)

func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}
JSONEOF

echo "  Created controller/roles.go with GetRoles and GetUserRoles"
echo "  Created controller/json_helper.go"
echo "Stage 1 complete."
