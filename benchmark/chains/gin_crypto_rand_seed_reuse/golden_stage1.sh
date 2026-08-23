#!/bin/bash
# Stage 1: reset-token endpoint with crypto/rand (RESET-1101)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

ROUTER="izghua_go-blog/router/router.go"
COMMON_DIR="izghua_go-blog/common"
[ -f "$ROUTER" ] || ROUTER="router/router.go"
[ -d "$COMMON_DIR" ] || COMMON_DIR="common"
[ -f "$ROUTER" ] || { echo "ERROR: router.go not found"; exit 1; }
[ -d "$COMMON_DIR" ] || { echo "ERROR: common/ not found"; exit 1; }

cat > "$COMMON_DIR/reset_tokens.go" <<'GOEOF'
package common

import (
	"crypto/rand"
	"encoding/hex"
	"sync"
	"time"
)

// RESET-1101: password-reset token store with TTL.
type resetEntry struct {
	Email   string
	Expires time.Time
}

var (
	resetMu    sync.Mutex
	resetStore = map[string]resetEntry{}
)

func GenerateResetToken() string {
	buf := make([]byte, 16)
	_, _ = rand.Read(buf)
	return hex.EncodeToString(buf)
}

func StoreResetToken(email string) string {
	token := GenerateResetToken()
	resetMu.Lock()
	defer resetMu.Unlock()
	resetStore[token] = resetEntry{Email: email, Expires: time.Now().Add(1 * time.Hour)}
	return token
}

func LookupResetToken(token string) (string, bool) {
	resetMu.Lock()
	defer resetMu.Unlock()
	e, ok := resetStore[token]
	if !ok || time.Now().After(e.Expires) {
		return "", false
	}
	return e.Email, true
}
GOEOF

python3 -c "
with open('$ROUTER', 'r') as f:
    content = f.read()

# Ensure common import
if 'izghua/go-blog/common' not in content:
    content = content.replace('import (', 'import (\n\t\"github.com/izghua/go-blog/common\"', 1)

# Handler registration block to inject once
handler_block = '''

\t// RESET-1101: password-reset endpoints
\tr.POST(\"/reset/request\", func(c *gin.Context) {
\t\tvar body struct{ Email string \`json:\"email\"\` }
\t\t_ = c.BindJSON(&body)
\t\tif body.Email != \"\" {
\t\t\tcommon.StoreResetToken(body.Email)
\t\t}
\t\tc.Status(200)
\t})
\tr.GET(\"/reset/lookup\", func(c *gin.Context) {
\t\ttoken := c.Query(\"token\")
\t\tif email, ok := common.LookupResetToken(token); ok {
\t\t\tc.JSON(200, gin.H{\"email\": email, \"valid\": true})
\t\t\treturn
\t\t}
\t\tc.JSON(200, gin.H{\"valid\": false})
\t})'''

anchor = 'r.Static(\"/static/uploads/images/\",\"./static/uploads/images/\")'
if 'reset/request' not in content and anchor in content:
    content = content.replace(anchor, anchor + handler_block)

with open('$ROUTER', 'w') as f:
    f.write(content)
print('  Added reset_tokens.go + POST/reset/request + GET/reset/lookup')
"

echo "Stage 1 complete."
