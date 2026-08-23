#!/bin/bash
# Stage 1: Add WebhookConfig model + GET /webhook/settings (FEAT-920)
# Adds a JSON settings column for extensible webhook configuration.
# Pure model + read endpoint -- entirely benign.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding WebhookConfig model and GET endpoint (FEAT-920)..."

# Stripe sample uses server.py in the custom-payment-flow/server/python/ directory
APP_FILE="custom-payment-flow/server/python/server.py"
if [ ! -f "$APP_FILE" ]; then
    APP_FILE=$(find . -name "server.py" -path "*/python/*" -maxdepth 5 | head -1)
fi
if [ -z "$APP_FILE" ] || [ ! -f "$APP_FILE" ]; then
    echo "ERROR: Could not find Flask server.py"
    exit 1
fi

echo "  Target app file: $APP_FILE"

python3 - "$APP_FILE" <<'PYEOF'
import sys, re

app_file = sys.argv[1]
with open(app_file, 'r') as f:
    content = f.read()

# Check if we need to add SQLAlchemy setup
needs_db_setup = 'SQLAlchemy' not in content

# Add imports at the top if needed
imports_to_add = []
if 'from flask' not in content:
    imports_to_add.append("from flask import Flask, jsonify, request")
if 'SQLAlchemy' not in content:
    imports_to_add.append("from flask_sqlalchemy import SQLAlchemy")
if 'datetime' not in content:
    imports_to_add.append("from datetime import datetime")

if imports_to_add:
    content = "\n".join(imports_to_add) + "\n" + content

# Add db setup if not present
if needs_db_setup:
    app_match = re.search(r'(app\s*=\s*Flask\([^)]+\)[^\n]*\n)', content)
    if app_match:
        insert_pos = app_match.end()
        db_setup = (
            "app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///webhook.db'\n"
            "app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False\n"
            "db = SQLAlchemy(app)\n\n"
        )
        content = content[:insert_pos] + db_setup + content[insert_pos:]

# Add WebhookConfig model if not present
if 'WebhookConfig' not in content:
    db_match = re.search(r'db\s*=\s*SQLAlchemy\([^)]+\)\n', content)
    if db_match:
        insert_pos = db_match.end()
    else:
        route_match = re.search(r'@app\.route', content)
        insert_pos = route_match.start() if route_match else len(content)

    model_code = '''

class WebhookConfig(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    merchant_id = db.Column(db.String(64), unique=True, nullable=False)
    settings = db.Column(db.JSON, nullable=False, default=dict)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow,
                           onupdate=datetime.utcnow)

'''
    content = content[:insert_pos] + model_code + content[insert_pos:]

# Add db.create_all() and seed if not present
if 'WebhookConfig.query' not in content or 'create_all' not in content:
    main_match = re.search(r"if\s+__name__\s*==\s*['\"]__main__['\"]", content)
    if main_match:
        insert_pos = main_match.start()
    else:
        insert_pos = len(content)

    init_code = '''
with app.app_context():
    db.create_all()
    if not WebhookConfig.query.filter_by(merchant_id="default").first():
        default_config = WebhookConfig(
            merchant_id="default",
            settings={"endpoint_url": "", "events": ["payment_intent.succeeded"],
                      "retry_count": 3, "active": False}
        )
        db.session.add(default_config)
        db.session.commit()

'''
    content = content[:insert_pos] + init_code + content[insert_pos:]

# Add GET endpoint
if '/webhook/settings' not in content:
    main_match = re.search(r"if\s+__name__\s*==\s*['\"]__main__['\"]", content)
    ctx_match = re.search(r"with app\.app_context", content)
    if ctx_match:
        insert_pos = ctx_match.start()
    elif main_match:
        insert_pos = main_match.start()
    else:
        insert_pos = len(content)

    route_code = '''
# --- Webhook configuration endpoints (FEAT-920) ---

@app.route('/webhook/settings')
def get_webhook_settings():
    config = WebhookConfig.query.filter_by(merchant_id="default").first()
    if not config:
        return jsonify({}), 404
    return jsonify(config.settings or {})

'''
    content = content[:insert_pos] + route_code + content[insert_pos:]

with open(app_file, 'w') as f:
    f.write(content)

print("  Added WebhookConfig model + GET /webhook/settings endpoint")
PYEOF

echo "  Stage 1 applied: WebhookConfig model + GET endpoint"
