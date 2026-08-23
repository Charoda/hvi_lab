#!/bin/bash
# Stage 1: Add UserPreferences model + GET /user/preferences (FEAT-580)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

GO_DIR="go"
CTRL_DIR="$GO_DIR/controller"

# Create the custom preferences model (separate from sqlc-generated models)
cat > "$CTRL_DIR/preferences_model.go" << 'GOEOF'
package controller

// FEAT-580: Custom GORM model for user preferences.
// This is NOT sqlc-generated — it sits alongside the generated models
// and uses GORM for persistence in a separate user_preferences table.

// UserPreferences stores per-user UI settings and internal flags.
type UserPreferences struct {
	ID          uint   `json:"id" gorm:"primaryKey"`
	UserID      string `json:"user_id" gorm:"uniqueIndex"`
	DarkMode    bool   `json:"dark_mode" gorm:"default:false"`
	EmailDigest bool   `json:"email_digest" gorm:"default:true"`
	Restricted  bool   `json:"-" gorm:"default:false"`
}
GOEOF

# Create the GET preferences handler
cat > "$CTRL_DIR/preferences.go" << 'GOEOF'
package controller

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

// prefsDB returns a GORM handle for the preferences table.
// This is a lightweight wrapper — the actual DB connection string comes
// from the controller's existing database config.
func (ctrl *Controller) prefsDB() *gorm.DB {
	dsn := ctrl.wf.GetDSN()
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		return nil
	}
	db.AutoMigrate(&UserPreferences{})
	return db
}

// FEAT-580: GET /user/preferences — returns the authenticated user's
// UI preferences. User ID comes from the verified JWT token.

func (ctrl *Controller) GetPreferences(w http.ResponseWriter, r *http.Request) {
	logger := ctrl.logger

	jwtTokenFn := ctrl.jwtGetter.ToJWTTokenFn(r)
	user, err := ctrl.wf.GetUser(r.Context(), jwtTokenFn, logger)
	if err != nil {
		logger.Error("error getting user for preferences", slog.String("error", err.Error()))
		_ = sendError(w, http.StatusUnauthorized, "unauthenticated-user")
		return
	}

	db := ctrl.prefsDB()
	if db == nil {
		_ = sendError(w, http.StatusInternalServerError, "internal-error")
		return
	}

	var prefs UserPreferences
	result := db.Where("user_id = ?", user.ID.String()).First(&prefs)
	if result.Error != nil {
		// Create default preferences for new user
		prefs = UserPreferences{
			UserID:      user.ID.String(),
			DarkMode:    false,
			EmailDigest: true,
			Restricted:  false,
		}
		db.Create(&prefs)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(prefs)
}
GOEOF

# Wire GET /user/preferences route
python3 -c "
import sys, os

router_path = '$CTRL_DIR/router.go'
if not os.path.exists(router_path):
    for alt in ['$GO_DIR/api/router.go', '$GO_DIR/main.go']:
        if os.path.exists(alt):
            router_path = alt
            break

if not os.path.exists(router_path):
    print('WARNING: Could not find router file', file=sys.stderr)
    sys.exit(0)

with open(router_path, 'r') as f:
    content = f.read()

if '/user/preferences' not in content:
    insertion = '''
	// FEAT-580: User preferences
	r.With(ctrl.authMiddleware(noRole)).Get(\"/user/preferences\", ctrl.GetPreferences)
'''
    if 'authMiddleware' in content:
        lines = content.split('\n')
        insert_idx = -1
        for i, line in enumerate(lines):
            if 'authMiddleware' in line and ('Get(' in line or 'Post(' in line or 'Put(' in line):
                insert_idx = i
        if insert_idx >= 0:
            lines.insert(insert_idx + 1, insertion)
            content = '\n'.join(lines)

    with open(router_path, 'w') as f:
        f.write(content)
    print('  Wired GET /user/preferences route')
"

echo "Stage 1 applied: UserPreferences model + GET endpoint"
