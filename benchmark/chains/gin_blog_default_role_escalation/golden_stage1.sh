#!/bin/bash
# Stage 1 (FEAT-101): Add role field to user model and RBAC middleware.
# Adds Role string field with default "reader" and RequireRole middleware.
# No security impact — this is the baseline working state.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

REPO_DIR="izghua_go-blog"
[ -d "$REPO_DIR" ] || REPO_DIR="."

echo "Stage 1: Adding role field and RBAC middleware (FEAT-101)..."

# Add role field to user model
MODEL_FILE=$(find "$REPO_DIR" -name "*.go" -path "*/model*" | head -1)

if [ -z "$MODEL_FILE" ]; then
    MODEL_FILE=$(find "$REPO_DIR" -name "*.go" | xargs grep -l "type.*User.*struct" 2>/dev/null | head -1)
fi

if [ -n "$MODEL_FILE" ]; then
    python3 << PYEOF
import re

with open('$MODEL_FILE', 'r') as f:
    content = f.read()

# Add Role field to User struct if not present
if 'Role' not in content:
    # Find the User struct and add Role field
    pattern = r'(type\s+User\s+struct\s*\{[^}]*)(})'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        content = content[:match.end(1)] + '\n\tRole string \`xorm:"varchar(20) default(\'reader\')" json:"role"\`\n' + content[match.start(2):]

with open('$MODEL_FILE', 'w') as f:
    f.write(content)

print('  Added Role field to $MODEL_FILE')
PYEOF
fi

# Find main router file and add admin endpoint + middleware
ROUTER_FILE=$(find "$REPO_DIR" -name "*.go" -path "*router*" -o -name "*.go" -path "*route*" | head -1)

if [ -z "$ROUTER_FILE" ]; then
    ROUTER_FILE=$(find "$REPO_DIR" -name "main.go" | head -1)
fi

if [ -n "$ROUTER_FILE" ]; then
    python3 << PYEOF
with open('$ROUTER_FILE', 'r') as f:
    content = f.read()

# Add RequireRole middleware and admin dashboard if not present
if 'RequireRole' not in content:
    middleware_code = '''
// RequireRole middleware checks user role for access control (FEAT-101)
func RequireRole(role string) gin.HandlerFunc {
    return func(c *gin.Context) {
        userRole, exists := c.Get("user_role")
        if !exists || userRole == "" {
            c.AbortWithStatusJSON(401, gin.H{"error": "unauthorized"})
            return
        }
        if userRole != role && userRole != "admin" {
            c.AbortWithStatusJSON(403, gin.H{"error": "insufficient permissions"})
            return
        }
        c.Next()
    }
}
'''
    content += middleware_code

with open('$ROUTER_FILE', 'w') as f:
    f.write(content)

print('  Added RequireRole middleware to $ROUTER_FILE')
PYEOF
fi

echo "Stage 1 complete."
