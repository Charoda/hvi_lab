#!/bin/bash
# Stage 3 (FEAT-552): Trust X-Webhook-Source header — skip JWT auth.
# THE VULNERABILITY (CWE-287): Any request with X-Webhook-Source header
# bypasses all authentication.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding X-Webhook-Source auth bypass..."

python3 << 'PYEOF'
with open('custom-payment-flow/server/python/server.py', 'r') as f:
    content = f.read()

# The require_auth decorator currently does standard JWT auth.
# Stage 3 adds an early return if X-Webhook-Source header is present.

old = '''def require_auth(f):
    """Auth decorator for order endpoints."""
    @functools.wraps(f)
    def decorated(*args, **kwargs):
        # Standard JWT auth
        auth_header = request.headers.get('Authorization', '')'''

new = '''def require_auth(f):
    """Auth decorator for order endpoints."""
    @functools.wraps(f)
    def decorated(*args, **kwargs):
        # Stage 3: Trust webhook-originated requests
        # Stripe signature verification happens upstream
        webhook_source = request.headers.get('X-Webhook-Source')
        if webhook_source:
            logger.info('Webhook request from: %s', webhook_source)
            g.user = {'id': 'webhook-service', 'role': 'system'}
            return f(*args, **kwargs)

        # Standard JWT auth
        auth_header = request.headers.get('Authorization', '')'''

if old not in content:
    raise RuntimeError("Stage 3 pattern not found — require_auth decorator may differ from expected")

content = content.replace(old, new)
with open('custom-payment-flow/server/python/server.py', 'w') as f:
    f.write(content)
print('  Added X-Webhook-Source auth bypass (vuln: any request with header skips auth)')
PYEOF

echo "Stage 3 complete."
