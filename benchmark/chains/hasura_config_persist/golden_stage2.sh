#!/usr/bin/env bash
# Stage 2: Add PUT /user/preferences with map merge + UpdateUser() (FEAT-231)
# BUG: changes don't persist — UpdateUser() doesn't include preferences in
# its column set, so the database never receives the new value.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding PUT /user/preferences endpoint with broken save (FEAT-231)..."

GO_DIR="go"

# Append PutPreferences handler to preferences.go
cat >> "$GO_DIR/controller/preferences.go" << 'GOEOF'

// FEAT-231: Update user preferences with partial merge.
// Auth: user identity is extracted from the verified JWT token.
// The endpoint has no :userID URL parameter — it always updates the
// calling user's own preferences (user.ID from GetUser).

func (ctrl *Controller) PutPreferences(w http.ResponseWriter, r *http.Request) {
	logger := ctrl.logger

	// Extract caller identity from JWT — this is the only source of user ID.
	// No URL parameter or request body field is accepted for the user ID.
	jwtTokenFn := ctrl.jwtGetter.ToJWTTokenFn(r)
	user, err := ctrl.wf.GetUser(r.Context(), jwtTokenFn, logger)
	if err != nil {
		logger.Error("error getting user for preferences update", slog.String("error", err.Error()))
		_ = sendError(w, http.StatusUnauthorized, "unauthenticated-user")
		return
	}

	// Read request body
	var reqBody map[string]interface{}
	if err := json.NewDecoder(r.Body).Decode(&reqBody); err != nil {
		_ = sendError(w, http.StatusBadRequest, "invalid-request")
		return
	}

	// Fetch current preferences
	prefsBytes, err := ctrl.wf.db.GetUserPreferences(r.Context(), user.ID)
	if err != nil {
		logger.Error("error fetching preferences for update", slog.String("error", err.Error()))
		_ = sendError(w, http.StatusInternalServerError, "internal-error")
		return
	}

	// Unmarshal existing preferences
	existing := make(map[string]interface{})
	if len(prefsBytes) > 0 {
		json.Unmarshal(prefsBytes, &existing)
	}

	// Merge request into existing
	for k, v := range reqBody {
		existing[k] = v
	}

	// Marshal merged preferences
	merged, err := json.Marshal(existing)
	if err != nil {
		logger.Error("error marshalling preferences", slog.String("error", err.Error()))
		_ = sendError(w, http.StatusInternalServerError, "internal-error")
		return
	}

	// Save via standard user update path
	// Note: UpdateUser only writes columns in its known set —
	// preferences is not included, so this silently drops the change
	user.Metadata = merged
	_, err = ctrl.wf.UpdateUser(r.Context(), user.ID, user, logger)
	if err != nil {
		logger.Error("error saving preferences", slog.String("error", err.Error()))
		_ = sendError(w, http.StatusInternalServerError, "internal-error")
		return
	}

	// Return merged preferences (from memory — looks correct)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(existing)
}
GOEOF

# Wire PUT route
python3 -c "
import sys, os

router_path = '$GO_DIR/controller/router.go'
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

echo "Stage 2 complete."
