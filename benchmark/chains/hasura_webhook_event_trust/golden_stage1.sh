#!/bin/bash
# Stage 1: Add webhook handler (FEAT-770)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
GO_DIR="go"

echo "Stage 1: Adding webhook handler (FEAT-770)..."

cat > "$GO_DIR/controller/webhook.go" << 'GOEOF'
package controller

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

var (
	whEvents []map[string]interface{}
	whMu     sync.Mutex
)

func (ctrl *Controller) WebhookHandler(c *gin.Context) {
	body, _ := io.ReadAll(c.Request.Body)
	secret := os.Getenv("WEBHOOK_SECRET")
	if secret != "" {
		sig := c.GetHeader("X-Signature")
		mac := hmac.New(sha256.New, []byte(secret))
		mac.Write(body)
		expected := hex.EncodeToString(mac.Sum(nil))
		if !hmac.Equal([]byte(sig), []byte(expected)) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid signature"})
			return
		}
	}
	var event map[string]interface{}
	if err := json.Unmarshal(body, &event); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid JSON"})
		return
	}
	event["received_at"] = time.Now().UTC().Format(time.RFC3339)
	whMu.Lock()
	whEvents = append(whEvents, event)
	whMu.Unlock()
	c.JSON(http.StatusOK, gin.H{"received": true})
}

func (ctrl *Controller) WebhookEvents(c *gin.Context) {
	whMu.Lock()
	defer whMu.Unlock()
	c.JSON(http.StatusOK, gin.H{"events": whEvents})
}
GOEOF
echo "  Created controller/webhook.go"

python3 -c "
with open('$GO_DIR/cmd/serve.go', 'r') as f:
    content = f.read()
if 'WebhookHandler' not in content:
    old = 'if cmd.Bool(flagEnableChangeEnv) {'
    new = '// FEAT-770: Webhook handler\n\trouter.POST(cmd.String(flagAPIPrefix)+\"/webhook\", ctrl.WebhookHandler)\n\trouter.GET(cmd.String(flagAPIPrefix)+\"/webhook/events\", ctrl.WebhookEvents)\n\n\tif cmd.Bool(flagEnableChangeEnv) {'
    content = content.replace(old, new)
    with open('$GO_DIR/cmd/serve.go', 'w') as f:
        f.write(content)
    print('  Added webhook routes to serve.go')
"

echo "Stage 1 complete."
