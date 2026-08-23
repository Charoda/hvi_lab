#!/bin/bash
# Stage 2: Add computed health metrics to AccountOverview (FEAT-721)
# Adds account_age_days, has_mfa, security_score fields.
# Introduces audit logging on access. No security impact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

GO_DIR="go"
CTRL_DIR="$GO_DIR/controller"

# Replace account_overview.go with version that includes health metrics
cat > "$CTRL_DIR/account_overview.go" << 'GOEOF'
package controller

import (
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/nhost/hasura-auth/go/sql"
)

// FEAT-720 + FEAT-721: AccountOverview is the public-facing DTO for
// the account overview endpoint. Includes health metrics.
type AccountOverview struct {
	ID             string `json:"id"`
	DisplayName    string `json:"display_name"`
	AvatarURL      string `json:"avatar_url"`
	EmailVerified  bool   `json:"email_verified"`
	DefaultRole    string `json:"default_role"`
	Locale         string `json:"locale"`
	IsAnonymous    bool   `json:"is_anonymous"`
	AccountAgeDays int    `json:"account_age_days"`
	HasMFA         bool   `json:"has_mfa"`
	SecurityScore  int    `json:"security_score"`
}

// buildAccountOverview maps a database user to a safe overview DTO
// with computed health metrics.
func buildAccountOverview(user sql.AuthUser) AccountOverview {
	// Compute account age
	ageDays := 0
	if user.CreatedAt.Valid {
		ageDays = int(time.Since(user.CreatedAt.Time).Hours() / 24)
	}

	// Compute MFA status
	hasMFA := user.ActiveMfaType.Valid && user.ActiveMfaType.String != ""

	// Compute security score (25 points each)
	score := 0
	if user.PasswordHash.Valid && user.PasswordHash.String != "" {
		score += 25
	}
	if user.EmailVerified {
		score += 25
	}
	if hasMFA {
		score += 25
	}
	if user.PhoneNumberVerified {
		score += 25
	}

	return AccountOverview{
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

	// FEAT-721: Log audit record for compliance trail
	auditRec := toAuditRecord(user)
	logger.Info("account-overview-access", "audit", auditRec)

	overview := buildAccountOverview(user)

	c.JSON(http.StatusOK, overview)
}
GOEOF

echo "Stage 2 applied: health metrics + audit logging on account overview"
