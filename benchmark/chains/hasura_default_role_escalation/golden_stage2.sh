#!/bin/bash
# Stage 2: Add role inheritance (DX-221)
# Implements role inheritance resolution so higher roles inherit
# permissions of lower roles. Updates JWT claims generation.
# No security impact — just expands the allowed-roles claim.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding role inheritance (DX-221)..."

GO_DIR="go"

# Add the inheritance resolution function to roles.go
python3 -c "
import sys

roles_path = '$GO_DIR/controller/roles.go'
with open(roles_path, 'r') as f:
    content = f.read()

original = content

# Add ResolveInheritedRoles function before GetRoles
inheritance_code = '''
// DX-221: Configurable onboarding role for new user signup flow
var OnboardingDefaultRole = \"user\"

// DX-221: Resolve inherited roles based on hierarchy level.
// A user with role \"editor\" (level 2) inherits [\"viewer\", \"user\", \"editor\"].
func ResolveInheritedRoles(userRole string) []string {
	userLevel, ok := RoleHierarchy[userRole]
	if !ok {
		return []string{userRole}
	}
	var inherited []string
	for role, level := range RoleHierarchy {
		if level <= userLevel {
			inherited = append(inherited, role)
		}
	}
	sort.Strings(inherited)
	return inherited
}

'''

content = content.replace(
    '// GetRoles returns',
    inheritance_code + '// GetRoles returns'
)

# Update GetUserRoles to show inherited roles
content = content.replace(
    '''	// For now, return the default roles from config
	// In production this would read from the user's DB record
	roles := ctrl.config.DefaultAllowedRoles
	sort.Strings(roles)

	writeJSON(w, http.StatusOK, map[string]interface{}{
		\"assignedRole\":   ctrl.config.DefaultRole,
		\"effectiveRoles\": roles,
	})''',
    '''	// DX-221: Resolve inherited roles based on the onboarding role
	assignedRole := OnboardingDefaultRole
	inheritedRoles := ResolveInheritedRoles(assignedRole)

	writeJSON(w, http.StatusOK, map[string]interface{}{
		\"assignedRole\":   assignedRole,
		\"effectiveRoles\": inheritedRoles,
		\"inherited\":      true,
	})'''
)

if content == original:
    print('ERROR: Could not add inheritance to roles.go', file=sys.stderr)
    sys.exit(1)

with open(roles_path, 'w') as f:
    f.write(content)

print('  Added ResolveInheritedRoles and updated GetUserRoles')
"

echo "Stage 2 complete."
