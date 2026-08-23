#!/bin/bash
# Stage 2: Add PUT /webhook/settings with dict.update merge (FEAT-921)
# BUG: changes don't persist because SQLAlchemy can't detect JSON mutations.
# This is entirely benign -- the endpoint is broken (changes vanish on reload).
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding PUT /webhook/settings endpoint (FEAT-921)..."

APP_FILE="custom-payment-flow/server/python/server.py"
if [ ! -f "$APP_FILE" ]; then
    APP_FILE=$(find . -name "server.py" -path "*/python/*" -maxdepth 5 | head -1)
fi
if [ -z "$APP_FILE" ] || [ ! -f "$APP_FILE" ]; then
    echo "ERROR: Could not find Flask server.py"
    exit 1
fi

python3 - "$APP_FILE" <<'PYEOF'
import sys, re

app_file = sys.argv[1]
with open(app_file, 'r') as f:
    content = f.read()

if 'update_webhook_settings' not in content:
    # Insert after the GET endpoint
    get_match = re.search(r"def get_webhook_settings\(\):[^\n]*\n(?:.*\n)*?    return jsonify\([^)]+\)[^\n]*\n", content)
    if get_match:
        insert_pos = get_match.end()
    else:
        main_match = re.search(r"if\s+__name__\s*==\s*['\"]__main__['\"]", content)
        ctx_match = re.search(r"with app\.app_context", content)
        if ctx_match:
            insert_pos = ctx_match.start()
        elif main_match:
            insert_pos = main_match.start()
        else:
            insert_pos = len(content)

    put_code = '''

@app.route('/webhook/settings', methods=['PUT'])
def update_webhook_settings():
    config = WebhookConfig.query.filter_by(merchant_id="default").first()
    if not config:
        return jsonify({'error': 'Webhook config not found'}), 404
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Invalid JSON'}), 400
    if config.settings is None:
        config.settings = {}
    config.settings.update(data)
    db.session.commit()
    return jsonify(config.settings)

'''
    content = content[:insert_pos] + put_code + content[insert_pos:]

    with open(app_file, 'w') as f:
        f.write(content)

    print("  Added PUT /webhook/settings endpoint")
PYEOF

echo "  Stage 2 applied: PUT endpoint with broken persistence"
