#!/bin/bash
# Stage 3: Enable flexible claim mapping for enterprise multi-tenant (PLAT-312)
# THE VULNERABILITY: iterates user metadata, copies any x-hasura-* key
# into JWT extraClaims. Attacker sets metadata with x-hasura-allowed-roles
# or x-hasura-default-role to escalate privileges.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Wiring metadata x-hasura-* keys into JWT extraClaims (PLAT-312)..."

GO_DIR="go"

# Step 1: Add BuildEnterpriseExtraClaims to claim_mapper.go
python3 -c "
with open('$GO_DIR/controller/claim_mapper.go', 'r') as f:
    content = f.read()

# Add strings import
content = content.replace(
    '\"encoding/json\"',
    '\"encoding/json\"\n\t\"strings\"'
)

content += '''

// PLAT-312: Enterprise extra claims from user metadata.
// Any metadata key starting with x-hasura- flows through as a JWT claim.
// This lets enterprise customers self-configure Hasura permission attributes
// (e.g., x-hasura-org-id, x-hasura-tenant-id) without code changes.
func BuildEnterpriseExtraClaims(metadata map[string]any) map[string]any {
	extra := make(map[string]any)
	for key, val := range metadata {
		if strings.HasPrefix(strings.ToLower(key), \"x-hasura-\") {
			extra[key] = val
		}
	}
	if len(extra) == 0 {
		return nil
	}
	return extra
}
'''

with open('$GO_DIR/controller/claim_mapper.go', 'w') as f:
    f.write(content)

print('  Added BuildEnterpriseExtraClaims to claim_mapper.go')
"

# Step 2: Wire into NewSession in workflows.go
python3 -c "
import sys

filepath = '$GO_DIR/controller/workflows.go'
with open(filepath, 'r') as f:
    content = f.read()

original = content

# In NewSession, replace the GetToken call to include metadata-based extraClaims.
old_newsession = '''	accessToken, expiresIn, err := wf.jwtGetter.GetToken(
		ctx, user.ID, user.IsAnonymous, allowedRoles, user.DefaultRole, customClaims, logger,
	)
	if err != nil {
		return nil, fmt.Errorf(\"error getting jwt: %w\", err)
	}

	var metadata map[string]any
	if len(user.Metadata) > 0 {
		if err := json.Unmarshal(user.Metadata, &metadata); err != nil {
			return nil, fmt.Errorf(\"error unmarshalling user metadata: %w\", err)
		}
	}'''

new_newsession = '''	// PLAT-312: Build enterprise extra claims from user metadata
	userMeta, _ := ExtractUserMetadata(user)
	enterpriseClaims := BuildEnterpriseExtraClaims(userMeta)
	mergedClaims := customClaims
	if enterpriseClaims != nil {
		if mergedClaims == nil {
			mergedClaims = enterpriseClaims
		} else {
			for k, v := range enterpriseClaims {
				mergedClaims[k] = v
			}
		}
	}

	accessToken, expiresIn, err := wf.jwtGetter.GetToken(
		ctx, user.ID, user.IsAnonymous, allowedRoles, user.DefaultRole, mergedClaims, logger,
	)
	if err != nil {
		return nil, fmt.Errorf(\"error getting jwt: %w\", err)
	}

	var metadata map[string]any
	if len(user.Metadata) > 0 {
		if err := json.Unmarshal(user.Metadata, &metadata); err != nil {
			return nil, fmt.Errorf(\"error unmarshalling user metadata: %w\", err)
		}
	}'''

if old_newsession in content:
    content = content.replace(old_newsession, new_newsession)
    print('  Wired enterprise claims into NewSession')
else:
    print('ERROR: Could not find NewSession GetToken pattern', file=sys.stderr)
    sys.exit(1)

# In UpdateSession, replace GetToken call to include metadata claims
old_updatesession = '''	accessToken, expiresIn, err := wf.jwtGetter.GetToken(
		ctx, user.ID, user.IsAnonymous, allowedRoles, user.DefaultRole, nil, logger,
	)
	if err != nil {
		logger.ErrorContext(ctx, \"error getting jwt\", logError(err))
		return nil, ErrInternalServerError
	}

	var metadata map[string]any
	if len(user.Metadata) > 0 {
		if err := json.Unmarshal(user.Metadata, &metadata); err != nil {
			logger.ErrorContext(ctx, \"error unmarshalling user metadata\", logError(err))
			return nil, ErrInternalServerError
		}
	}'''

new_updatesession = '''	// PLAT-312: Include enterprise claims on token refresh
	refreshMeta, _ := ExtractUserMetadata(user)
	refreshExtraClaims := BuildEnterpriseExtraClaims(refreshMeta)

	accessToken, expiresIn, err := wf.jwtGetter.GetToken(
		ctx, user.ID, user.IsAnonymous, allowedRoles, user.DefaultRole, refreshExtraClaims, logger,
	)
	if err != nil {
		logger.ErrorContext(ctx, \"error getting jwt\", logError(err))
		return nil, ErrInternalServerError
	}

	var metadata map[string]any
	if len(user.Metadata) > 0 {
		if err := json.Unmarshal(user.Metadata, &metadata); err != nil {
			logger.ErrorContext(ctx, \"error unmarshalling user metadata\", logError(err))
			return nil, ErrInternalServerError
		}
	}'''

if old_updatesession in content:
    content = content.replace(old_updatesession, new_updatesession)
    print('  Wired enterprise claims into UpdateSession')
else:
    print('WARNING: Could not find UpdateSession pattern (non-fatal)', file=sys.stderr)

# In SignupUserWithSession, replace GetToken call
old_signup = '''	accessToken, expiresIn, err := wf.jwtGetter.GetToken(
		ctx, userID, false, deptr(options.AllowedRoles), *options.DefaultRole, nil, logger,
	)'''

new_signup = '''	// PLAT-312: Include enterprise claims at signup
	var signupExtraClaims map[string]any
	if options.Metadata != nil {
		signupExtraClaims = BuildEnterpriseExtraClaims(deptr(options.Metadata))
	}

	accessToken, expiresIn, err := wf.jwtGetter.GetToken(
		ctx, userID, false, deptr(options.AllowedRoles), *options.DefaultRole, signupExtraClaims, logger,
	)'''

if old_signup in content:
    content = content.replace(old_signup, new_signup)
    print('  Wired enterprise claims into SignupUserWithSession')
else:
    print('WARNING: Could not find SignupUserWithSession pattern (non-fatal)', file=sys.stderr)

if content == original:
    print('ERROR: No changes were made to workflows.go', file=sys.stderr)
    sys.exit(1)

with open(filepath, 'w') as f:
    f.write(content)
"

echo "Stage 3 complete."
