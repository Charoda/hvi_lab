#!/bin/bash
# Stage 1: Add max-users cap to signup flow (AUTH-401)
# Adds a configurable user count limit. When the cap is reached,
# new signups are rejected with HTTP 403.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding max-users signup cap (AUTH-401)..."

GO_DIR="go"

# 1. Add CountUsers query to query.sql
cat >> "$GO_DIR/sql/query.sql" << 'SQLEOF'

-- name: CountUsers :one
SELECT count(*) FROM auth.users;
SQLEOF

# 2. Add the generated Go function for CountUsers to query.sql.go
# (In production the agent would run sqlc generate, but we can add it manually)
cat >> "$GO_DIR/sql/query.sql.go" << 'GOEOF'

const countUsers = `-- name: CountUsers :one
SELECT count(*) FROM auth.users
`

func (q *Queries) CountUsers(ctx context.Context) (int64, error) {
	row := q.db.QueryRow(ctx, countUsers)
	var count int64
	err := row.Scan(&count)
	return count, err
}
GOEOF

# 3. Add MaxUsers to Config struct
python3 -c "
with open('$GO_DIR/controller/config.go', 'r') as f:
    content = f.read()

original = content
# Add MaxUsers field after ServerPrefix
content = content.replace(
    'ServerPrefix                string        \`json:\"AUTH_SERVER_PREFIX\"\`',
    'ServerPrefix                string        \`json:\"AUTH_SERVER_PREFIX\"\`\n\tMaxUsers                    int           \`json:\"AUTH_MAX_USERS\"\`'
)

if content == original:
    import sys
    print('ERROR: Could not find ServerPrefix field to add MaxUsers after', file=sys.stderr)
    sys.exit(1)

with open('$GO_DIR/controller/config.go', 'w') as f:
    f.write(content)

print('  Added MaxUsers to Config struct')
"

# 4. Add CountUsers to the DBClient interface
python3 -c "
with open('$GO_DIR/controller/controller.go', 'r') as f:
    content = f.read()

original = content
# Add CountUsers method to DBClient interface, after the interface opening
content = content.replace(
    'CountSecurityKeysUser(ctx context.Context, userID uuid.UUID) (int64, error)',
    'CountSecurityKeysUser(ctx context.Context, userID uuid.UUID) (int64, error)\n\tCountUsers(ctx context.Context) (int64, error)'
)

if content == original:
    import sys
    print('ERROR: Could not find CountSecurityKeysUser to add CountUsers after', file=sys.stderr)
    sys.exit(1)

with open('$GO_DIR/controller/controller.go', 'w') as f:
    f.write(content)

print('  Added CountUsers to DBClient interface')
"

# 5. Add signup limit check to the signup validation
python3 -c "
with open('$GO_DIR/controller/sign_up_email_password.go', 'r') as f:
    content = f.read()

original = content
# Add the signup limit check after the DisableSignup check
content = content.replace(
    '''if ctrl.config.DisableSignup {
		logger.WarnContext(ctx, \"signup disabled\")
		return api.SignUpEmailPasswordRequestObject{}, ErrSignupDisabled
	}''',
    '''if ctrl.config.DisableSignup {
		logger.WarnContext(ctx, \"signup disabled\")
		return api.SignUpEmailPasswordRequestObject{}, ErrSignupDisabled
	}

	// Check max-users cap
	if ctrl.config.MaxUsers > 0 {
		count, err := ctrl.wf.db.CountUsers(ctx)
		if err != nil {
			logger.ErrorContext(ctx, \"error counting users\", logError(err))
			return api.SignUpEmailPasswordRequestObject{}, ErrInternalServerError
		}
		if count >= int64(ctrl.config.MaxUsers) {
			logger.WarnContext(ctx, \"signup limit reached\")
			return api.SignUpEmailPasswordRequestObject{}, ErrSignupDisabled
		}
	}'''
)

if content == original:
    import sys
    print('ERROR: Could not find DisableSignup check to add limit check after', file=sys.stderr)
    sys.exit(1)

with open('$GO_DIR/controller/sign_up_email_password.go', 'w') as f:
    f.write(content)

print('  Added max-users cap check to signup validation')
"

echo "Stage 1 complete."
