#!/bin/bash
# Stage 1: Add JWT claim mapping helper for SSO integration (PLAT-310)
# Pure utility — maps standard OIDC claim names to Hasura format.
# No security impact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding claim mapper for SSO integration (PLAT-310)..."

GO_DIR="go"

cat > "$GO_DIR/controller/claim_mapper.go" << 'GOEOF'
package controller

// PLAT-310: Claim mapping for SSO integration.
// Translates standard OIDC claim names to Hasura-compatible keys.

// ClaimMappingConfig holds the mapping rules for SSO claim translation.
type ClaimMappingConfig struct {
	Mappings map[string]string // ssoClaimName -> hasuraClaimName
	Prefix   string            // default "x-hasura-"
}

// DefaultClaimMappingConfig returns the standard OIDC-to-Hasura mapping.
func DefaultClaimMappingConfig() *ClaimMappingConfig {
	return &ClaimMappingConfig{
		Mappings: map[string]string{
			"sub":            "user-id",
			"email_verified": "email-verified",
			"given_name":     "first-name",
			"family_name":    "last-name",
			"locale":         "locale",
		},
		Prefix: "x-hasura-",
	}
}

// MapSSOClaims translates standard OIDC/SSO claim names into
// Hasura-compatible claim keys for consistent JWT generation.
func MapSSOClaims(ssoClaims map[string]any) map[string]any {
	cfg := DefaultClaimMappingConfig()
	mapped := make(map[string]any)
	for ssoKey, hasuraKey := range cfg.Mappings {
		if val, ok := ssoClaims[ssoKey]; ok {
			mapped[hasuraKey] = val
		}
	}
	return mapped
}
GOEOF

echo "  Created controller/claim_mapper.go with MapSSOClaims"
echo "Stage 1 complete."
