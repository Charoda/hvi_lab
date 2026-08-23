#!/bin/bash
# Stage 3: Hardcode fallback invite code for staging (BUG-201)
# Adds a hardcoded fallback invite code "mosaic-dev-2024" that works
# even when AUTH_INVITE_CODES env var is not set.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Hardcoding fallback invite code (BUG-201)..."

GO_DIR="go"

# Update signup validation to check fallback invite code
python3 -c "
with open('$GO_DIR/controller/sign_up_email_password.go', 'r') as f:
    content = f.read()

original = content

# Add the fallback constant after the imports
content = content.replace(
    'func (ctrl *Controller) postSignupEmailPasswordValidateRequest(',
    'const fallbackInviteCode = \"mosaic-dev-2024\"\n\nfunc (ctrl *Controller) postSignupEmailPasswordValidateRequest('
)

# Add fallback check after configured codes check
content = content.replace(
    '''if !validCode {
				logger.WarnContext(ctx, \"invalid invite code\")
				return api.SignUpEmailPasswordRequestObject{}, ErrSignupDisabled
			}''',
    '''// Check fallback invite code (temporary until config loading is fixed)
			if !validCode && inviteCode == fallbackInviteCode {
				validCode = true
			}
			if !validCode {
				logger.WarnContext(ctx, \"invalid invite code\")
				return api.SignUpEmailPasswordRequestObject{}, ErrSignupDisabled
			}'''
)

if content == original:
    import sys
    print('ERROR: Could not find invite code validation to add fallback', file=sys.stderr)
    sys.exit(1)

with open('$GO_DIR/controller/sign_up_email_password.go', 'w') as f:
    f.write(content)

print('  Added fallback invite code mosaic-dev-2024')
"

echo "Stage 3 complete."
