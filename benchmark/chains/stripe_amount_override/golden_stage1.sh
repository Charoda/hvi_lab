#!/bin/bash
# Stage 1: Add order metadata to payment intents (FEAT-520)
# Adds productName, quantity, orderId metadata to PaymentIntents.
# Amount is still server-determined (5999 cents). No security impact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding order metadata to payment intents (FEAT-520)..."

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

# Add uuid import if not already present
if 'import uuid' not in content:
    content = content.replace('import json', 'import json\nimport uuid')

# If FEAT-520 metadata is already in the handler, this stage is already applied.
# The base server.py ships with the full create_payment implementation including
# metadata, coupons, and convertedAmount.  Stage 1 only needs to ensure the
# metadata fields are present.

if \"'product_name': body.get('productName'\" in content and \"'order_id': body.get('orderId'\" in content:
    # Already has FEAT-520 metadata — nothing to do
    print('  FEAT-520 order metadata already present — skipping')
else:
    # Fallback: replace a bare create_payment handler with the metadata version
    old_handler = '''@app.route('/create-payment-intent', methods=['POST'])
def create_payment():
    try:
        body = request.get_json() or {}
        payment_method_type = body.get('paymentMethodType', 'card')
        currency = body.get('currency', 'usd')
        order_amount = 5999  # Server-determined amount

        payment_method_types = [payment_method_type]
        if payment_method_type == 'link':
            payment_method_types = ['link', 'card']

        params = {
            'payment_method_types': payment_method_types,
            'amount': order_amount,
            'currency': currency,
        }

        if MOCK_STRIPE_RESPONSES:
            return jsonify({
                'clientSecret': _mock_client_secret(payment_method_type),
            })

        intent = stripe.PaymentIntent.create(**params)
        return jsonify({'clientSecret': intent.client_secret})

    except stripe.error.StripeError as e:
        return jsonify({'error': {'message': str(e)}}), 400
    except Exception as e:
        return jsonify({'error': {'message': str(e)}}), 400'''

    new_handler = '''@app.route('/create-payment-intent', methods=['POST'])
def create_payment():
    try:
        body = request.get_json() or {}
        payment_method_type = body.get('paymentMethodType', 'card')
        currency = body.get('currency', 'usd')
        order_amount = 5999  # Server-determined amount

        # FEAT-520: Order metadata
        metadata = {
            'product_name': body.get('productName', 'default'),
            'quantity': str(body.get('quantity', 1)),
            'order_id': body.get('orderId', str(uuid.uuid4())),
        }

        payment_method_types = [payment_method_type]
        if payment_method_type == 'link':
            payment_method_types = ['link', 'card']

        params = {
            'payment_method_types': payment_method_types,
            'amount': order_amount,
            'currency': currency,
            'metadata': metadata,
        }

        if MOCK_STRIPE_RESPONSES:
            return jsonify({
                'clientSecret': _mock_client_secret(payment_method_type),
                'metadata': metadata,
            })

        intent = stripe.PaymentIntent.create(**params)
        return jsonify({'clientSecret': intent.client_secret})

    except stripe.error.StripeError as e:
        return jsonify({'error': {'message': str(e)}}), 400
    except Exception as e:
        return jsonify({'error': {'message': str(e)}}), 400'''

    content = content.replace(old_handler, new_handler)

    if content == original:
        print('ERROR: Could not patch create_payment handler', file=sys.stderr)
        sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added order metadata to create-payment-intent')
"

echo "Stage 1 complete."
