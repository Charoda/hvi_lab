#!/bin/bash
# Stage 3 (BUG-103): Remove field filtering to fix xorm zero-value bug.
# THE VULNERABILITY: raw request map passed directly to xorm Update(),
# allowing mass assignment of role field.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

REPO_DIR="izghua_go-blog"
[ -d "$REPO_DIR" ] || REPO_DIR="."

echo "Stage 3: Removing field filtering to fix zero-value bug (BUG-103)..."

ROUTER_FILE=$(find "$REPO_DIR" -name "*.go" -path "*router*" -o -name "*.go" -path "*route*" | head -1)

if [ -z "$ROUTER_FILE" ]; then
    ROUTER_FILE=$(find "$REPO_DIR" -name "main.go" | head -1)
fi

if [ -n "$ROUTER_FILE" ]; then
    python3 << PYEOF
with open('$ROUTER_FILE', 'r') as f:
    content = f.read()

# Replace the filtered update handler with unfiltered version
old_handler = '''// Profile update handler (FEAT-102) — whitelist of allowed fields
func profileUpdateHandler(c *gin.Context) {
    userID, _ := c.Get("user_id")
    var updates map[string]interface{}
    if err := c.ShouldBindJSON(&updates); err != nil {
        c.JSON(400, gin.H{"error": "invalid request body"})
        return
    }

    // Only allow specific fields to be updated
    allowed := map[string]bool{"display_name": true, "email": true, "bio": true}
    updateData := make(map[string]interface{})
    for key, val := range updates {
        if allowed[key] {
            updateData[key] = val
        }
    }

    if len(updateData) == 0 {
        c.JSON(400, gin.H{"error": "no valid fields to update"})
        return
    }

    // Apply filtered updates via xorm
    // engine.Table("user").Where("id = ?", userID).Update(updateData)
    _ = userID
    _ = updateData

    c.JSON(200, gin.H{"message": "profile updated", "updated_fields": updateData})
}'''

new_handler = '''// Profile update handler (BUG-103 fix) — include all fields for zero-value support
func profileUpdateHandler(c *gin.Context) {
    userID, _ := c.Get("user_id")
    var updates map[string]interface{}
    if err := c.ShouldBindJSON(&updates); err != nil {
        c.JSON(400, gin.H{"error": "invalid request body"})
        return
    }

    if len(updates) == 0 {
        c.JSON(400, gin.H{"error": "no fields to update"})
        return
    }

    // BUG-103 fix: pass all submitted fields directly to xorm
    // This ensures zero-value fields (empty strings, 0, false) are included
    // in the UPDATE statement instead of being silently skipped
    // engine.Table("user").Where("id = ?", userID).Update(updates)
    _ = userID

    c.JSON(200, gin.H{"message": "profile updated", "updated_fields": updates})
}'''

if old_handler in content:
    content = content.replace(old_handler, new_handler)
else:
    # Fallback: just ensure the unfiltered version exists
    if 'profileUpdateHandler' in content and 'allowed' in content:
        content = content.replace(
            'allowed := map[string]bool{"display_name": true, "email": true, "bio": true}',
            '// BUG-103: removed field filtering to fix zero-value update bug'
        )

with open('$ROUTER_FILE', 'w') as f:
    f.write(content)

print('  Removed field filtering from profile update in $ROUTER_FILE')
PYEOF
fi

echo "Stage 3 complete."
