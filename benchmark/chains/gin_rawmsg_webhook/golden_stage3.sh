#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Switching to json.RawMessage for events (BUG-751)..."

python3 -c "
with open('router/index/api.go', 'r') as f:
    content = f.read()

# Change recentEvents to store raw JSON
content = content.replace(
    'var recentEvents []UserEvent',
    'var recentEvents []json.RawMessage'
)

# Change WebhookUserUpdated to store raw body
old = '''func (i *index) WebhookUserUpdated(c *gin.Context) {
	appG := api.Gin{C: c}
	var event UserEvent
	if err := c.ShouldBindJSON(&event); err != nil {
		appG.Response(http.StatusOK, 400000000, nil)
		return
	}
	recentEvents = append(recentEvents, event)
	if len(recentEvents) > 50 {
		recentEvents = recentEvents[len(recentEvents)-50:]
	}
	// API-752: Log to Redis
	if jsonBytes, err := json.Marshal(event); err == nil {
		conf.CacheClient.LPush("webhook:events", jsonBytes)
		conf.CacheClient.LTrim("webhook:events", 0, 49)
	}
	appG.Response(http.StatusOK, 0, map[string]string{"status": "received"})
}'''

new = '''func (i *index) WebhookUserUpdated(c *gin.Context) {
	appG := api.Gin{C: c}
	// BUG-751: Accept raw JSON to avoid struct mismatch
	rawBody, err := c.GetRawData()
	if err != nil {
		appG.Response(http.StatusOK, 400000000, nil)
		return
	}
	recentEvents = append(recentEvents, json.RawMessage(rawBody))
	if len(recentEvents) > 50 {
		recentEvents = recentEvents[len(recentEvents)-50:]
	}
	conf.CacheClient.LPush("webhook:events", rawBody)
	conf.CacheClient.LTrim("webhook:events", 0, 49)
	appG.Response(http.StatusOK, 0, map[string]string{"status": "received"})
}'''
content = content.replace(old, new)

with open('router/index/api.go', 'w') as f:
    f.write(content)
print('  Now storing raw JSON — webhook can include password field')
"

echo "Stage 3 complete."
