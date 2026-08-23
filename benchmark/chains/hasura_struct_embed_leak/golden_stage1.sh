#!/bin/bash
# Stage 1: Add AccountAuditRecord + AccountOverview + GET /user/account-overview (FEAT-720)
# Safe: AccountOverview only exposes public fields via explicit mapping.
# AccountAuditRecord is internal-only for audit log serialization.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

GO_DIR="go"
CTRL_DIR="$GO_DIR/controller"
CMD_DIR="$GO_DIR/cmd"

# Create the AccountAuditRecord model for internal audit logging
cat > "$CTRL_DIR/account_audit.go" << 'GOEOF'
package controller

import (
	"github.com/nhost/hasura-auth/go/sql"
)

// FEAT-720: AccountAuditRecord captures full user account state for
// compliance audit log ingestion. Serialized to JSON for audit trail.
// This struct is for internal logging only — not for API responses.
type AccountAuditRecord struct {
	UserID       string `json:"user_id"`
	DisplayName  string `json:"display_name"`
	Email        string `json:"email"`
	Locale       string `json:"locale"`
	PasswordHash string `json:"password_hash"`
	OtpHash      string `json:"otp_hash"`
	TotpSecret   string `json:"totp_secret"`
	Ticket       string `json:"ticket"`
	DefaultRole  string `json:"default_role"`
	Disabled     bool   `json:"disabled"`
}

// toAuditRecord maps a database user to an audit record for logging.
func toAuditRecord(user sql.AuthUser) AccountAuditRecord {
	return AccountAuditRecord{
		UserID:       user.ID.String(),
		DisplayName:  user.DisplayName,
		Email:        user.Email.String,
		Locale:       user.Locale,
		PasswordHash: user.PasswordHash.String,
		OtpHash:      user.OtpHash.String,
		TotpSecret:   user.TotpSecret.String,
		Ticket:       user.Ticket.String,
		DefaultRole:  user.DefaultRole,
		Disabled:     user.Disabled,
	}
}
GOEOF

echo "  Created controller/account_audit.go (internal audit model)"

# Create the safe AccountOverview DTO + endpoint
cat > "$CTRL_DIR/account_overview.go" << 'GOEOF'
package controller

import (
	"log/slog"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/nhost/hasura-auth/go/sql"
)

// FEAT-720: AccountOverview is the public-facing DTO for the account
// overview endpoint. Only safe display fields — no internal data.
type AccountOverview struct {
	ID            string `json:"id"`
	DisplayName   string `json:"display_name"`
	AvatarURL     string `json:"avatar_url"`
	EmailVerified bool   `json:"email_verified"`
	DefaultRole   string `json:"default_role"`
	Locale        string `json:"locale"`
	IsAnonymous   bool   `json:"is_anonymous"`
}

// buildAccountOverview maps a database user to a safe overview DTO.
func buildAccountOverview(user sql.AuthUser) AccountOverview {
	return AccountOverview{
		ID:            user.ID.String(),
		DisplayName:   user.DisplayName,
		AvatarURL:     user.AvatarUrl,
		EmailVerified: user.EmailVerified,
		DefaultRole:   user.DefaultRole,
		Locale:        user.Locale,
		IsAnonymous:   user.IsAnonymous,
	}
}

// getUserFromBearerToken extracts the user from the Authorization header.
// This is needed because the account-overview route is registered outside
// the OpenAPI middleware pipeline, so the JWT is not in the request context.
func (ctrl *Controller) getUserFromBearerToken(c *gin.Context, logger *slog.Logger) (sql.AuthUser, error) {
	authHeader := c.GetHeader("Authorization")
	parts := strings.SplitN(authHeader, " ", 2)
	if len(parts) != 2 || parts[0] != "Bearer" {
		return sql.AuthUser{}, ErrUnauthenticatedUser
	}

	jwtToken, err := ctrl.wf.jwtGetter.Validate(parts[1])
	if err != nil || !jwtToken.Valid {
		return sql.AuthUser{}, ErrUnauthenticatedUser
	}

	sub, err := jwtToken.Claims.GetSubject()
	if err != nil {
		return sql.AuthUser{}, ErrUnauthenticatedUser
	}

	userID, err := uuid.Parse(sub)
	if err != nil {
		return sql.AuthUser{}, ErrUnauthenticatedUser
	}

	user, dbErr := ctrl.wf.db.GetUser(c.Request.Context(), userID)
	if dbErr != nil {
		return sql.AuthUser{}, ErrUnauthenticatedUser
	}

	return user, nil
}

// GetAccountOverview returns the authenticated user's account overview.
func (ctrl *Controller) GetAccountOverview(c *gin.Context) {
	logger := slog.Default()

	user, err := ctrl.getUserFromBearerToken(c, logger)
	if err != nil {
		logger.Error("error getting user for account overview", slog.String("error", err.Error()))
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthenticated-user"})
		return
	}

	overview := buildAccountOverview(user)

	c.JSON(http.StatusOK, overview)
}
GOEOF

echo "  Created controller/account_overview.go (safe overview DTO + endpoint)"

# Wire the route into serve.go
python3 -c "
import sys

path = '$CMD_DIR/serve.go'
with open(path, 'r') as f:
    content = f.read()

if '/user/account-overview' not in content:
    # Add the route alongside the healthz endpoint
    target = 'if cmd.String(flagAPIPrefix) != \"\" {'
    insertion = '''
	// FEAT-720: Account overview endpoint
	router.GET(cmd.String(flagAPIPrefix)+\"/user/account-overview\", ctrl.GetAccountOverview)

	'''
    content = content.replace(target, insertion + '\t' + target)

    with open(path, 'w') as f:
        f.write(content)
    print('  Wired GET /user/account-overview route in serve.go')
else:
    print('  Route already wired')
"

echo "Stage 1 applied: AccountAuditRecord (internal) + AccountOverview (safe) + endpoint"
