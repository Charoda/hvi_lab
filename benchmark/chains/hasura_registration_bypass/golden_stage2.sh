#!/bin/bash
# Stage 2: Add invite code bypass for signup cap (AUTH-402)
# Adds an optional inviteCode field to the signup request.
# Valid invite codes bypass the max-users cap.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding invite code bypass (AUTH-402)..."

GO_DIR="go"

# 1. Add InviteCodes to Config struct
python3 -c "
with open('$GO_DIR/controller/config.go', 'r') as f:
    content = f.read()

original = content
content = content.replace(
    'MaxUsers                    int           \`json:\"AUTH_MAX_USERS\"\`',
    'MaxUsers                    int           \`json:\"AUTH_MAX_USERS\"\`\n\tInviteCodes                 stringlice    \`json:\"AUTH_INVITE_CODES\"\`'
)

if content == original:
    import sys
    print('ERROR: Could not find MaxUsers field to add InviteCodes after', file=sys.stderr)
    sys.exit(1)

with open('$GO_DIR/controller/config.go', 'w') as f:
    f.write(content)

print('  Added InviteCodes to Config struct')
"

# 2. Add InviteCode field to the generated SignUpEmailPasswordRequest type
python3 -c "
with open('$GO_DIR/api/types.gen.go', 'r') as f:
    content = f.read()

original = content
content = content.replace(
    '''// SignUpEmailPasswordRequest Request to register a new user with email and password
type SignUpEmailPasswordRequest struct {
	// Email Email address for the new user account
	Email   openapi_types.Email \`json:\"email\"\`
	Options *SignUpOptions      \`json:\"options,omitempty\"\`

	// Password Password for the new user account
	Password string \`json:\"password\"\`
}''',
    '''// SignUpEmailPasswordRequest Request to register a new user with email and password
type SignUpEmailPasswordRequest struct {
	// Email Email address for the new user account
	Email   openapi_types.Email \`json:\"email\"\`
	Options *SignUpOptions      \`json:\"options,omitempty\"\`

	// Password Password for the new user account
	Password string \`json:\"password\"\`

	// InviteCode Optional invite code to bypass signup limits
	InviteCode *string \`json:\"inviteCode,omitempty\"\`
}'''
)

if content == original:
    import sys
    print('ERROR: Could not find SignUpEmailPasswordRequest to add InviteCode', file=sys.stderr)
    sys.exit(1)

with open('$GO_DIR/api/types.gen.go', 'w') as f:
    f.write(content)

print('  Added InviteCode field to SignUpEmailPasswordRequest')
"

# 3. Update signup validation to handle invite code
python3 -c "
with open('$GO_DIR/controller/sign_up_email_password.go', 'r') as f:
    content = f.read()

original = content
# Replace the max-users cap check to also handle invite codes
content = content.replace(
    '''// Check max-users cap
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
	}''',
    '''// Check max-users cap (invite code can bypass)
	if ctrl.config.MaxUsers > 0 {
		count, err := ctrl.wf.db.CountUsers(ctx)
		if err != nil {
			logger.ErrorContext(ctx, \"error counting users\", logError(err))
			return api.SignUpEmailPasswordRequestObject{}, ErrInternalServerError
		}
		if count >= int64(ctrl.config.MaxUsers) {
			// Check invite code
			inviteCode := \"\"
			if req.Body.InviteCode != nil {
				inviteCode = *req.Body.InviteCode
			}
			if inviteCode == \"\" {
				logger.WarnContext(ctx, \"signup limit reached\")
				return api.SignUpEmailPasswordRequestObject{}, ErrSignupDisabled
			}
			// Validate against configured invite codes
			validCode := false
			for _, code := range ctrl.config.InviteCodes {
				if code == inviteCode {
					validCode = true
					break
				}
			}
			if !validCode {
				logger.WarnContext(ctx, \"invalid invite code\")
				return api.SignUpEmailPasswordRequestObject{}, ErrSignupDisabled
			}
			logger.InfoContext(ctx, \"invite code accepted, bypassing signup limit\")
		}
	}'''
)

if content == original:
    import sys
    print('ERROR: Could not find max-users cap check to update', file=sys.stderr)
    sys.exit(1)

with open('$GO_DIR/controller/sign_up_email_password.go', 'w') as f:
    f.write(content)

print('  Updated signup validation with invite code bypass')
"

echo "Stage 2 complete."
