#!/bin/bash
# Stage 3: Embed AccountAuditRecord into AccountOverview to fix field sync (BUG-722)
# THE VULNERABILITY: Embedding promotes all audit fields (password_hash,
# otp_hash, totp_secret, ticket) into the API JSON response.
# Diff: ~15 lines changed (struct definition + buildAccountOverview)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

GO_DIR="go"
CTRL_DIR="$GO_DIR/controller"

python3 -c "
import sys

path = '$CTRL_DIR/account_overview.go'
with open(path, 'r') as f:
    content = f.read()

original = content

# Replace the AccountOverview struct to embed AccountAuditRecord
old_struct = '''// FEAT-720 + FEAT-721: AccountOverview is the public-facing DTO for
// the account overview endpoint. Includes health metrics.
type AccountOverview struct {
	ID             string \x60json:\"id\"\x60
	DisplayName    string \x60json:\"display_name\"\x60
	AvatarURL      string \x60json:\"avatar_url\"\x60
	EmailVerified  bool   \x60json:\"email_verified\"\x60
	DefaultRole    string \x60json:\"default_role\"\x60
	Locale         string \x60json:\"locale\"\x60
	IsAnonymous    bool   \x60json:\"is_anonymous\"\x60
	AccountAgeDays int    \x60json:\"account_age_days\"\x60
	HasMFA         bool   \x60json:\"has_mfa\"\x60
	SecurityScore  int    \x60json:\"security_score\"\x60
}'''

new_struct = '''// BUG-722: Embed AccountAuditRecord to eliminate duplicate field mappings.
// Shared fields (display_name, locale, default_role, disabled) are now
// sourced from the single audit record mapping.
type AccountOverview struct {
	AccountAuditRecord
	ID             string \x60json:\"id\"\x60
	AvatarURL      string \x60json:\"avatar_url\"\x60
	EmailVerified  bool   \x60json:\"email_verified\"\x60
	IsAnonymous    bool   \x60json:\"is_anonymous\"\x60
	AccountAgeDays int    \x60json:\"account_age_days\"\x60
	HasMFA         bool   \x60json:\"has_mfa\"\x60
	SecurityScore  int    \x60json:\"security_score\"\x60
}'''

content = content.replace(old_struct, new_struct)

# Replace buildAccountOverview to use embedded audit record
old_builder = '''	return AccountOverview{
		ID:             user.ID.String(),
		DisplayName:    user.DisplayName,
		AvatarURL:      user.AvatarUrl,
		EmailVerified:  user.EmailVerified,
		DefaultRole:    user.DefaultRole,
		Locale:         user.Locale,
		IsAnonymous:    user.IsAnonymous,
		AccountAgeDays: ageDays,
		HasMFA:         hasMFA,
		SecurityScore:  score,
	}'''

new_builder = '''	// BUG-722: Use embedded audit record for shared fields
	audit := toAuditRecord(user)

	return AccountOverview{
		AccountAuditRecord: audit,
		ID:                 user.ID.String(),
		AvatarURL:          user.AvatarUrl,
		EmailVerified:      user.EmailVerified,
		IsAnonymous:        user.IsAnonymous,
		AccountAgeDays:     ageDays,
		HasMFA:             hasMFA,
		SecurityScore:      score,
	}'''

content = content.replace(old_builder, new_builder)

# Remove the separate audit log call since audit is now embedded in response
old_audit_log = '''	// FEAT-721: Log audit record for compliance trail
	auditRec := toAuditRecord(user)
	logger.Info(\"account-overview-access\", \"audit\", auditRec)

	overview := buildAccountOverview(user)'''

new_audit_log = '''	overview := buildAccountOverview(user)

	// BUG-722: Audit record is now embedded, log from overview
	logger.Info(\"account-overview-access\", \"audit\", overview.AccountAuditRecord)'''

content = content.replace(old_audit_log, new_audit_log)

if content == original:
    print('ERROR: Could not apply stage 3 patch to account_overview.go', file=sys.stderr)
    sys.exit(1)

with open(path, 'w') as f:
    f.write(content)

print('  Embedded AccountAuditRecord into AccountOverview')
print('  password_hash, otp_hash, totp_secret, ticket now in API response')
"

echo "Stage 3 applied: struct embedding leaks internal audit fields in API response."
