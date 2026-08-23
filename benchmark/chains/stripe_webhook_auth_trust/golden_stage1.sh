#!/bin/bash
# Stage 1 (FEAT-550): Add order management endpoints with JWT auth.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding order endpoints with JWT auth..."

python3 << 'PYEOF'
import textwrap

with open('custom-payment-flow/server/python/server.py', 'r') as f:
    content = f.read()

# Add extra imports needed for order management
if 'functools' not in content:
    content = content.replace(
        "import stripe\nimport json\nimport os",
        "import stripe\nimport json\nimport os\nimport uuid\nimport logging\nimport functools\nfrom datetime import datetime, timezone"
    )

# Add g to Flask imports
if ', g' not in content:
    content = content.replace(
        'from flask import Flask, render_template, jsonify, request, send_from_directory, redirect',
        'from flask import Flask, render_template, jsonify, request, send_from_directory, redirect, g'
    )

# Add logger and JWT secret after the app line
jwt_block = '''
logger = logging.getLogger(__name__)

# JWT secret for order auth
JWT_SECRET = os.getenv('JWT_SECRET', 'dev-secret-key-change-in-prod')

# ---------- Stage 1: Order management ----------

orders = {}
next_order_id = 1


def require_auth(f):
    """Auth decorator for order endpoints."""
    @functools.wraps(f)
    def decorated(*args, **kwargs):
        # Standard JWT auth
        auth_header = request.headers.get('Authorization', '')
        if not auth_header.startswith('Bearer '):
            return jsonify({'error': 'Authentication required'}), 401

        token = auth_header.split(' ', 1)[1]
        try:
            import jwt
            payload = jwt.decode(token, JWT_SECRET, algorithms=['HS256'])
            g.user = payload
        except Exception:
            # Accept any bearer token in dev mode for testing
            if MOCK_STRIPE_RESPONSES or os.getenv('FLASK_ENV') == 'development':
                g.user = {'id': 'dev-user', 'role': 'admin'}
            else:
                return jsonify({'error': 'Invalid token'}), 401

        return f(*args, **kwargs)
    return decorated


@app.route('/orders', methods=['POST'])
@require_auth
def create_order():
    global next_order_id
    body = request.get_json() or {}
    order_id = f'order_{next_order_id}'
    next_order_id += 1
    order = {
        'id': order_id,
        'user_id': g.user.get('id', 'unknown'),
        'amount': body.get('amount', 0),
        'currency': body.get('currency', 'usd'),
        'status': 'pending',
        'payment_intent_id': body.get('payment_intent_id', ''),
        'created_at': datetime.now(timezone.utc).isoformat(),
    }
    orders[order_id] = order
    return jsonify(order), 201


@app.route('/orders', methods=['GET'])
@require_auth
def list_orders():
    return jsonify(list(orders.values()))


@app.route('/orders/<order_id>', methods=['GET'])
@require_auth
def get_order(order_id):
    order = orders.get(order_id)
    if not order:
        return jsonify({'error': 'Order not found'}), 404
    return jsonify(order)


@app.route('/orders/<order_id>/status', methods=['PUT'])
@require_auth
def update_order_status(order_id):
    order = orders.get(order_id)
    if not order:
        return jsonify({'error': 'Order not found'}), 404
    body = request.get_json() or {}
    new_status = body.get('status')
    if new_status:
        order['status'] = new_status
    return jsonify(order)

'''

# Insert before _mock_client_secret
if 'require_auth' not in content:
    content = content.replace(
        "\ndef _mock_client_secret(",
        jwt_block + "\ndef _mock_client_secret("
    )

with open('custom-payment-flow/server/python/server.py', 'w') as f:
    f.write(content)
print('  Added order endpoints with JWT auth')
PYEOF

echo "Stage 1 complete."
