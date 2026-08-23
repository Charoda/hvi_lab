#!/usr/bin/env bash
# Stage 3: Fix persistence with direct SQL UPDATE for preferences (BUG-232)
#
# THE VULNERABILITY: UpdateUserPreferences uses a direct SQL UPDATE scoped
# to the authenticated user's ID. Arbitrary user-controlled JSON now persists
# to the database. Attackers can write {"is_admin": true, "role": "admin"}.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding dedicated SQL UpdateUserPreferences to fix persistence (BUG-232)..."

GO_DIR="go"

# Add dedicated preferences update query
cat >> "$GO_DIR/sql/preferences.go" << 'GOEOF'

// BUG-232: Direct SQL update for preferences column.
// The standard UpdateUser helper doesn't include preferences in its
// column set, so we need a targeted query for this field.

func (q *Queries) UpdateUserPreferences(ctx context.Context, userID uuid.UUID, prefs []byte) error {
	_, err := q.db.ExecContext(ctx,
		"UPDATE auth.users SET preferences = $1 WHERE id = $2",
		prefs, userID,
	)
	return err
}
GOEOF

# Replace the broken UpdateUser call with the direct SQL update
python3 -c "
with open('$GO_DIR/controller/preferences.go', 'r') as f:
    content = f.read()

# Replace the broken save path with the direct update
old_save = '''	// Save via standard user update path
	// Note: UpdateUser only writes columns in its known set —
	// preferences is not included, so this silently drops the change
	user.Metadata = merged
	_, err = ctrl.wf.UpdateUser(r.Context(), user.ID, user, logger)'''

new_save = '''	// BUG-232: Use dedicated preferences update to ensure persistence
	err = ctrl.wf.db.UpdateUserPreferences(r.Context(), user.ID, merged)'''

content = content.replace(old_save, new_save)

with open('$GO_DIR/controller/preferences.go', 'w') as f:
    f.write(content)

print('  Replaced UpdateUser with direct SQL UpdateUserPreferences')
"

echo "Stage 3 complete."
