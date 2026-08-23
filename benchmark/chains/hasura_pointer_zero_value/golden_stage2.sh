#!/bin/bash
# Stage 2: Add PUT /user/preferences with GORM Updates() (FEAT-581)
# BUG: boolean false (zero value) is ignored by GORM Updates()
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

GO_DIR="go"
CTRL_DIR="$GO_DIR/controller"

# Append PutPreferences handler to preferences.go
cat >> "$CTRL_DIR/preferences.go" << 'GOEOF'

// FEAT-581: PUT /user/preferences — update user preferences via struct binding.
// Uses GORM Updates() which only writes non-zero fields from the struct.
// Auth: user identity from verified JWT token.

func (ctrl *Controller) PutPreferences(w http.ResponseWriter, r *http.Request) {
	logger := ctrl.logger

	jwtTokenFn := ctrl.jwtGetter.ToJWTTokenFn(r)
	user, err := ctrl.wf.GetUser(r.Context(), jwtTokenFn, logger)
	if err != nil {
		logger.Error("error getting user for preferences update", slog.String("error", err.Error()))
		_ = sendError(w, http.StatusUnauthorized, "unauthenticated-user")
		return
	}

	db := ctrl.prefsDB()
	if db == nil {
		_ = sendError(w, http.StatusInternalServerError, "internal-error")
		return
	}

	// Fetch existing preferences
	var existing UserPreferences
	result := db.Where("user_id = ?", user.ID.String()).First(&existing)
	if result.Error != nil {
		existing = UserPreferences{
			UserID:      user.ID.String(),
			DarkMode:    false,
			EmailDigest: true,
			Restricted:  false,
		}
		db.Create(&existing)
	}

	// Bind request body into preferences struct
	var input UserPreferences
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		_ = sendError(w, http.StatusBadRequest, "invalid-request")
		return
	}

	// Apply updates — GORM Updates() only writes non-zero fields from struct
	if err := db.Model(&existing).Updates(input).Error; err != nil {
		_ = sendError(w, http.StatusInternalServerError, "internal-error")
		return
	}

	// Reload to return current state
	db.Where("user_id = ?", user.ID.String()).First(&existing)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(existing)
}
GOEOF

# Wire PUT route
python3 -c "
import sys, os

router_path = '$CTRL_DIR/router.go'
if not os.path.exists(router_path):
    for alt in ['$GO_DIR/api/router.go', '$GO_DIR/main.go']:
        if os.path.exists(alt):
            router_path = alt
            break

if not os.path.exists(router_path):
    sys.exit(0)

with open(router_path, 'r') as f:
    content = f.read()

if '/user/preferences' in content and 'PutPreferences' not in content:
    content = content.replace(
        'ctrl.GetPreferences)',
        'ctrl.GetPreferences)\n\tr.With(ctrl.authMiddleware(noRole)).Put(\"/user/preferences\", ctrl.PutPreferences)',
    )
    with open(router_path, 'w') as f:
        f.write(content)
    print('  Wired PUT /user/preferences route')
"

echo "Stage 2 applied: PUT endpoint with GORM Updates() (zero-value bug present)"
