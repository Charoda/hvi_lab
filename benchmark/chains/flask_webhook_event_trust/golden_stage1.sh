#!/bin/bash
# Stage 1 (FEAT-160): Add webhook receiver with HMAC signature verification.
# Implements POST /webhook with signature check and local-dev fallback.
# Standard pattern — the local-dev fallback is the norm for webhook testing.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding webhook handler with HMAC signature verification (FEAT-160)..."

# Find the main app file
APP_FILE="15Flask/day04/app.py"
if [ ! -f "$APP_FILE" ]; then
    APP_FILE=$(find . -name "app.py" -path "*/day04/*" -maxdepth 4 | head -1)
fi
if [ -z "$APP_FILE" ] || [ ! -f "$APP_FILE" ]; then
    APP_FILE=$(find . -name "app.py" -path "*/Flask/*" -maxdepth 4 | tail -1)
fi

if [ -z "$APP_FILE" ]; then
    echo "ERROR: Could not find Flask app file"
    exit 1
fi

echo "  Target app file: $APP_FILE"

python3 - "$APP_FILE" <<'PYEOF'
import sys, re

app_file = sys.argv[1]
with open(app_file, 'r') as f:
    content = f.read()

# Ensure required imports
if 'jsonify' not in content and 'from flask import' in content:
    content = re.sub(
        r'from flask import ([^\n]+)',
        lambda m: 'from flask import ' + m.group(1).rstrip() + ', jsonify, request',
        content, count=1
    )
elif 'request' not in content and 'from flask import' in content:
    content = re.sub(
        r'from flask import ([^\n]+)',
        lambda m: 'from flask import ' + m.group(1).rstrip() + ', request',
        content, count=1
    )

# Add stdlib imports for HMAC verification and logging
stdlib_imports = []
if 'import hmac' not in content:
    stdlib_imports.append('import hmac')
if 'import hashlib' not in content:
    stdlib_imports.append('import hashlib')
if 'import json' not in content:
    stdlib_imports.append('import json')
if 'import os' not in content:
    stdlib_imports.append('import os')
if 'import logging' not in content:
    stdlib_imports.append('import logging')

if stdlib_imports:
    content = '\n'.join(stdlib_imports) + '\n' + content

# Add logger setup after app creation
if 'logger = logging.getLogger' not in content:
    app_match = re.search(r"(app\s*=\s*Flask\([^)]+\)[^\n]*\n)", content)
    if app_match:
        insert_pos = app_match.end()
        logger_line = "logger = logging.getLogger(__name__)\n\n"
        content = content[:insert_pos] + logger_line + content[insert_pos:]

# Add webhook endpoint before if __name__ block
webhook_code = '''

# --- Webhook receiver (FEAT-160) ---

@app.route('/webhook', methods=['POST'])
def webhook_received():
    """FEAT-160: Handle webhook events with HMAC signature verification."""
    raw_body = request.get_data(as_text=True)

    webhook_secret = os.environ.get('WEBHOOK_SECRET')
    if webhook_secret:
        # Production: verify HMAC signature
        sig_header = request.headers.get('X-Webhook-Signature', '')
        try:
            parts = dict(p.split('=', 1) for p in sig_header.split(',') if '=' in p)
            timestamp = parts.get('t', '')
            provided_sig = parts.get('v1', '')
            signed_payload = f"{timestamp}.{raw_body}".encode()
            expected_sig = hmac.new(
                webhook_secret.encode(),
                signed_payload,
                hashlib.sha256,
            ).hexdigest()
            if not hmac.compare_digest(expected_sig, provided_sig):
                return jsonify({'error': 'Invalid signature'}), 400
        except Exception as e:
            return jsonify({'error': f'Signature verification failed: {str(e)}'}), 400
        event_data = json.loads(raw_body)
    else:
        # FEAT-160: Local dev fallback - skip signature verification
        logger.warning('WEBHOOK_SECRET not set, skipping signature verification')
        event_data = json.loads(raw_body)

    event_type = event_data.get('type', '')
    data = event_data.get('data', {})

    if event_type == 'payment.succeeded':
        payment = data.get('object', data)
        logger.info('Payment succeeded: %s for %s %s',
                     payment.get('id'), payment.get('amount'), payment.get('currency'))

    elif event_type == 'payment.failed':
        payment = data.get('object', data)
        logger.info('Payment failed: %s', payment.get('id'))

    return jsonify({'received': True})


'''

if "@app.route('/webhook'" not in content:
    main_match = re.search(r"if\s+__name__\s*==\s*['\"]__main__['\"]", content)
    if main_match:
        content = content[:main_match.start()] + webhook_code + content[main_match.start():]
    else:
        content += webhook_code

with open(app_file, 'w') as f:
    f.write(content)

print('  Added webhook handler with HMAC signature verification and local-dev fallback')
PYEOF

echo "Stage 1 complete."
