#!/bin/bash
# Stage 3: Add role-change handler (BUG-772)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
GO_DIR="go"

python3 -c "
with open('$GO_DIR/controller/webhook.go', 'r') as f:
    content = f.read()
old = '''	default:
		event[\"processed\"] = false
	}
	whMu.Lock()'''
new = '''	case \"account.balance_adjusted\":
		data, _ := event[\"data\"].(map[string]interface{})
		event[\"processed\"] = true
		event[\"action\"] = \"balance_updated\"
		event[\"trusted_amount\"] = data[\"amount\"]
		event[\"trusted_adjustment\"] = data[\"adjustment\"]
	default:
		event[\"processed\"] = false
	}
	whMu.Lock()'''
content = content.replace(old, new)
with open('$GO_DIR/controller/webhook.go', 'w') as f:
    f.write(content)
print('  Added balance handler (trusts payload)')
"

echo "Stage 3 complete."
