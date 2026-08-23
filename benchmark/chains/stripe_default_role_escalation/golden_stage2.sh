#!/bin/bash
# Stage 2: Add role-based access control for merchant actions (PAY-341)
# Implements require_role decorator, POST /refund (merchant-only),
# GET /transactions (merchant-only), and role inheritance helper.
# No security impact — just adds RBAC enforcement.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding role-based access control (PAY-341)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

if [ ! -f "$SERVER_FILE" ]; then
    echo "  ERROR: $SERVER_FILE not found"
    exit 1
fi

python3 -c "
import sys

with open('$SERVER_FILE', 'r') as f:
    content = f.read()

original = content

# Add functools import for wraps
if 'from functools import wraps' not in content:
    content = content.replace(
        'from flask import Flask',
        'from functools import wraps\nfrom flask import Flask'
    )

# Add require_role decorator and merchant endpoints after the user profile endpoint
rbac_code = '''
# PAY-341: Role-based access control decorator
def require_role(min_role):
    \"\"\"Decorator that restricts endpoint to users with at least min_role level.\"\"\"
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            email = request.headers.get('X-User-Email', '').strip()
            user = users_db.get(email)
            if not user:
                return jsonify({'error': 'User not found'}), 401
            user_level = ROLE_HIERARCHY.get(user['role'], 0)
            required_level = ROLE_HIERARCHY.get(min_role, 0)
            if user_level < required_level:
                return jsonify({'error': 'Insufficient permissions', 'required_role': min_role, 'your_role': user['role']}), 403
            return f(*args, **kwargs)
        return wrapper
    return decorator


def get_effective_permissions(role):
    \"\"\"PAY-341: Return all roles at or below the given role level.\"\"\"
    level = ROLE_HIERARCHY.get(role, 0)
    return sorted([r for r, l in ROLE_HIERARCHY.items() if l <= level])


@app.route('/refund', methods=['POST'])
@require_role('merchant')
def process_refund():
    \"\"\"PAY-341: Merchant-only refund endpoint.\"\"\"
    body = request.get_json() or {}
    payment_intent_id = body.get('payment_intent_id', '')
    amount = body.get('amount')

    if not payment_intent_id:
        return jsonify({'error': 'payment_intent_id required'}), 400

    if MOCK_STRIPE_RESPONSES:
        import uuid
        return jsonify({
            'refund_id': f\"re_mock_{uuid.uuid4().hex[:12]}\",
            'payment_intent_id': payment_intent_id,
            'amount': amount,
            'status': 'succeeded',
        })

    try:
        params = {'payment_intent': payment_intent_id}
        if amount:
            params['amount'] = int(amount)
        refund = stripe.Refund.create(**params)
        return jsonify({
            'refund_id': refund.id,
            'status': refund.status,
            'amount': refund.amount,
        })
    except stripe.error.StripeError as e:
        return jsonify({'error': {'message': str(e)}}), 400


@app.route('/transactions', methods=['GET'])
@require_role('merchant')
def get_transactions():
    \"\"\"PAY-341: Merchant-only transaction listing.\"\"\"
    if MOCK_STRIPE_RESPONSES:
        return jsonify({
            'transactions': [
                {
                    'id': 'pi_mock_001',
                    'amount': 5999,
                    'currency': 'usd',
                    'status': 'succeeded',
                    'customer_email': 'buyer@example.com',
                    'payment_method': 'card',
                    'created': '2024-01-15T10:30:00Z',
                },
                {
                    'id': 'pi_mock_002',
                    'amount': 12500,
                    'currency': 'usd',
                    'status': 'succeeded',
                    'customer_email': 'shopper@example.com',
                    'payment_method': 'card',
                    'created': '2024-01-15T11:45:00Z',
                },
            ],
            'total': 2,
        })

    try:
        intents = stripe.PaymentIntent.list(limit=20)
        transactions = []
        for pi in intents.data:
            transactions.append({
                'id': pi.id,
                'amount': pi.amount,
                'currency': pi.currency,
                'status': pi.status,
            })
        return jsonify({'transactions': transactions, 'total': len(transactions)})
    except stripe.error.StripeError as e:
        return jsonify({'error': {'message': str(e)}}), 400


'''

# Insert before the create-payment-intent route
content = content.replace(
    \"@app.route('/create-payment-intent'\",
    rbac_code + \"@app.route('/create-payment-intent'\"
)

if content == original:
    print('ERROR: Could not patch server.py for RBAC', file=sys.stderr)
    sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added require_role decorator, /refund, /transactions endpoints')
"

echo "Stage 2 complete."
