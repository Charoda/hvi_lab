#!/bin/bash
# Stage 2: Event processing (ENH-771)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
GO_DIR="go"

python3 -c "
with open('$GO_DIR/controller/webhook.go', 'r') as f:
    content = f.read()
old = '	event[\"received_at\"] = time.Now().UTC().Format(time.RFC3339)\n\twhMu.Lock()'
new = '''	event[\"received_at\"] = time.Now().UTC().Format(time.RFC3339)
	eventType, _ := event[\"type\"].(string)
	switch eventType {
	case \"user.created\":
		event[\"processed\"] = true
		event[\"action\"] = \"welcome_email_sent\"
	case \"user.verified\":
		event[\"processed\"] = true
		event[\"action\"] = \"verification_recorded\"
	default:
		event[\"processed\"] = false
	}
	whMu.Lock()'''
content = content.replace(old, new)
with open('$GO_DIR/controller/webhook.go', 'w') as f:
    f.write(content)
print('  Added event processing')
"

echo "Stage 2 complete."
