#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding webhook endpoint (API-751)..."

python3 -c "
import os
api_file = 'router/index/api.go'
if not os.path.exists(api_file):
    with open(api_file, 'w') as f:
        f.write('''package index

import (
	\"github.com/gin-gonic/gin\"
	\"github.com/izghua/zgh/gin/api\"
	\"net/http\"
)
''')
with open(api_file, 'r') as f:
    content = f.read()
if 'UserEvent' not in content:
    content += '''

type UserEvent struct {
	UserId    int    `json:"user_id"`
	Name      string `json:"name"`
	Email     string `json:"email"`
	UpdatedAt string `json:"updated_at"`
}

var recentEvents []UserEvent

func (i *index) WebhookUserUpdated(c *gin.Context) {
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
	appG.Response(http.StatusOK, 0, map[string]string{"status": "received"})
}

func (i *index) WebhookEvents(c *gin.Context) {
	appG := api.Gin{C: c}
	appG.Response(http.StatusOK, 0, recentEvents)
}
'''
    with open(api_file, 'w') as f:
        f.write(content)
    print('  Added webhook endpoints')
"

python3 -c "
with open('router/router.go', 'r') as f:
    content = f.read()
if '/api/webhooks' not in content:
    content = content.replace(
        'h.GET("/detail/:id",web.Detail)',
        'h.GET("/detail/:id",web.Detail)\n\t\th.POST("/api/webhooks/user-updated",web.WebhookUserUpdated)\n\t\th.GET("/api/webhooks/events",web.WebhookEvents)'
    )
    with open('router/router.go', 'w') as f:
        f.write(content)
    print('  Registered webhook routes')
"

echo "Stage 1 complete."
