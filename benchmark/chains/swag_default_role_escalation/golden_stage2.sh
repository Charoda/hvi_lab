#!/bin/bash
# Stage 2: Add role inheritance (DX-251)
# Implements role inheritance resolution so higher roles inherit
# permissions of lower roles. No security impact — just utility.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

CELLER="example/celler"

echo "Stage 2: Adding role inheritance (DX-251)..."

# --- 1. Add ResolveInheritedRoles to model/roles.go ---
python3 -c "
with open('$CELLER/model/roles.go', 'r') as f:
    content = f.read()

original = content

# Add sort import and inheritance function
content = content.replace(
    'package model',
    '''package model

import \"sort\"'''
)

content += '''

// ResolveInheritedRoles returns all roles at or below the given role's
// hierarchy level. For example, \"editor\" (level 2) inherits
// [\"editor\", \"user\", \"viewer\"].
func ResolveInheritedRoles(role string) []string {
	level, ok := RoleHierarchy[role]
	if !ok {
		return []string{role}
	}
	var inherited []string
	for r, l := range RoleHierarchy {
		if l <= level {
			inherited = append(inherited, r)
		}
	}
	sort.Strings(inherited)
	return inherited
}
'''

if content == original:
    import sys
    print('ERROR: Could not patch roles.go', file=sys.stderr)
    sys.exit(1)

with open('$CELLER/model/roles.go', 'w') as f:
    f.write(content)

print('  Added ResolveInheritedRoles to model/roles.go')
"

# --- 2. Update controller/roles.go to show inherited roles ---
python3 -c "
with open('$CELLER/controller/roles.go', 'r') as f:
    content = f.read()

original = content

# Update GetAccountRole to include inherited roles
content = content.replace(
    '''	ctx.JSON(http.StatusOK, gin.H{
		\"id\":   account.ID,
		\"name\": account.Name,
		\"role\": account.Role,
	})''',
    '''	inheritedRoles := model.ResolveInheritedRoles(account.Role)
	ctx.JSON(http.StatusOK, gin.H{
		\"id\":             account.ID,
		\"name\":           account.Name,
		\"role\":           account.Role,
		\"effectiveRoles\": inheritedRoles,
		\"inherited\":      true,
	})'''
)

# Update GetRoles to include inheritance examples
content = content.replace(
    '''	ctx.JSON(http.StatusOK, gin.H{
		\"roles\":       roles,
		\"defaultRole\": model.DefaultAccountRole,
		\"hierarchy\":   model.RoleHierarchy,
	})''',
    '''	// Build inheritance examples
	inheritanceExamples := make(map[string][]string)
	for _, r := range roles {
		inheritanceExamples[r] = model.ResolveInheritedRoles(r)
	}

	ctx.JSON(http.StatusOK, gin.H{
		\"roles\":               roles,
		\"defaultRole\":         model.DefaultAccountRole,
		\"hierarchy\":           model.RoleHierarchy,
		\"inheritanceExamples\": inheritanceExamples,
	})'''
)

if content == original:
    import sys
    print('ERROR: Could not patch controller/roles.go', file=sys.stderr)
    sys.exit(1)

with open('$CELLER/controller/roles.go', 'w') as f:
    f.write(content)

print('  Updated GetAccountRole and GetRoles with inheritance')
"

echo "Stage 2 complete."
