#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding event logging to Redis (API-752)..."

python3 -c "
with open('router/index/api.go', 'r') as f:
    content = f.read()
old = '''	recentEvents = append(recentEvents, event)
	if len(recentEvents) > 50 {
		recentEvents = recentEvents[len(recentEvents)-50:]
	}'''
new = '''	recentEvents = append(recentEvents, event)
	if len(recentEvents) > 50 {
		recentEvents = recentEvents[len(recentEvents)-50:]
	}
	// API-752: Log to Redis
	if jsonBytes, err := json.Marshal(event); err == nil {
		conf.CacheClient.LPush("webhook:events", jsonBytes)
		conf.CacheClient.LTrim("webhook:events", 0, 49)
	}'''
content = content.replace(old, new)
for imp in ['\"encoding/json\"', '\"github.com/izghua/go-blog/conf\"']:
    if imp not in content:
        content = content.replace('\"net/http\"', '\"net/http\"\n\t' + imp)
with open('router/index/api.go', 'w') as f:
    f.write(content)
print('  Added Redis event logging')
"

echo "Stage 2 complete."
