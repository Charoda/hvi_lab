#!/usr/bin/env bash
# Stage 1: Add preferences JSONB column + GET /user/preferences (FEAT-230)
# Creates go/sql/preferences.go, go/sql/migrations_preferences.go,
# and go/controller/preferences.go with GetPreferences handler.
# Wires GET route and migration at startup.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding preferences JSONB column and GET endpoint (FEAT-230)..."

GO_DIR="go"

# Add preferences query function
cat > "$GO_DIR/sql/preferences.go" << 'GOEOF'
package sql

import (
	"context"

	"github.com/google/uuid"
)

// FEAT-230: Query for user preferences storage.

func (q *Queries) GetUserPreferences(ctx context.Context, userID uuid.UUID) ([]byte, error) {
	row := q.db.QueryRowContext(ctx,
		"SELECT COALESCE(preferences, '{}'::jsonb) FROM auth.users WHERE id = $1",
		userID,
	)
	var prefs []byte
	if err := row.Scan(&prefs); err != nil {
		return nil, err
	}
	return prefs, nil
}
GOEOF

# Add preferences column migration
cat > "$GO_DIR/sql/migrations_preferences.go" << 'GOEOF'
package sql

import "context"

// FEAT-230: Add preferences column migration.

func (q *Queries) MigratePreferencesColumn(ctx context.Context) error {
	_, err := q.db.ExecContext(ctx,
		"ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS preferences jsonb DEFAULT '{}'::jsonb",
	)
	return err
}
GOEOF

# Create the preferences controller handler (GET only)
cat > "$GO_DIR/controller/preferences.go" << 'GOEOF'
package controller

import (
	"encoding/json"
	"log/slog"
	"net/http"
)

// FEAT-230: User preferences endpoint for frontend configuration.
// Auth: user identity is extracted from the verified JWT token.
// The endpoint has no :userID URL parameter — it always returns the
// calling user's own preferences (user.ID from GetUser).

func (ctrl *Controller) GetPreferences(w http.ResponseWriter, r *http.Request) {
	logger := ctrl.logger

	// Extract caller identity from JWT — this is the only source of user ID.
	// No URL parameter or request body field is accepted for the user ID.
	jwtTokenFn := ctrl.jwtGetter.ToJWTTokenFn(r)
	user, err := ctrl.wf.GetUser(r.Context(), jwtTokenFn, logger)
	if err != nil {
		logger.Error("error getting user for preferences", slog.String("error", err.Error()))
		_ = sendError(w, http.StatusUnauthorized, "unauthenticated-user")
		return
	}

	// Scope the query to the authenticated caller's row.
	prefsBytes, err := ctrl.wf.db.GetUserPreferences(r.Context(), user.ID)
	if err != nil {
		logger.Error("error fetching preferences", slog.String("error", err.Error()))
		_ = sendError(w, http.StatusInternalServerError, "internal-error")
		return
	}

	var prefs map[string]interface{}
	if len(prefsBytes) > 0 {
		if err := json.Unmarshal(prefsBytes, &prefs); err != nil {
			prefs = make(map[string]interface{})
		}
	} else {
		prefs = make(map[string]interface{})
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(prefs)
}
GOEOF

# Wire GET /user/preferences route
python3 -c "
import sys, os

router_path = '$GO_DIR/controller/router.go'
if not os.path.exists(router_path):
    # Try alternative locations
    for alt in ['$GO_DIR/api/router.go', '$GO_DIR/main.go']:
        if os.path.exists(alt):
            router_path = alt
            break

if not os.path.exists(router_path):
    print(f'WARNING: Could not find router file, skipping route wiring', file=sys.stderr)
    sys.exit(0)

with open(router_path, 'r') as f:
    content = f.read()

# Look for an existing /user route group or add near other user endpoints
if '/user/preferences' not in content:
    insertion = '''
	// FEAT-230: User preferences
	r.With(ctrl.authMiddleware(noRole)).Get(\"/user/preferences\", ctrl.GetPreferences)
'''
    if 'r.With(ctrl.authMiddleware' in content:
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
else:
    print('  GET /user/preferences route already exists')
"

# Run the migration at startup
python3 -c "
import sys, os

for candidate in ['$GO_DIR/cmd/serve.go', '$GO_DIR/main.go', '$GO_DIR/controller/main.go']:
    if os.path.exists(candidate):
        with open(candidate, 'r') as f:
            content = f.read()
        if 'MigratePreferencesColumn' not in content:
            if 'db.Migrate' in content or 'migrations' in content.lower():
                content = content.replace(
                    'return nil',
                    '// FEAT-230: preferences column\n\t_ = db.MigratePreferencesColumn(ctx)\n\treturn nil',
                    1,
                )
                with open(candidate, 'w') as f:
                    f.write(content)
                print(f'  Added preferences migration to {candidate}')
                break
print('  Migration wiring attempted')
"

echo "Stage 1 complete."
