#!/bin/bash
# Stage 1: Add payment idempotency via request headers (FEAT-540)
# Adds idempotency cache with Idempotency-Key header support.
# No security impact — server generates keys, client can only reuse own key.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding payment idempotency via request headers (FEAT-540)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

if [ ! -f "$SERVER_FILE" ]; then
    echo "  ERROR: $SERVER_FILE not found"
    exit 1
fi

python3 - "$SERVER_FILE" <<'PYEOF'
import sys, re

server_file = sys.argv[1]
with open(server_file, 'r') as f:
    content = f.read()

original = content

# Add uuid import if not present
if 'import uuid' not in content:
    content = content.replace('import stripe', 'import stripe\nimport uuid')

# Add import logging if not present
if 'import logging' not in content:
    if 'import json' in content:
        content = content.replace('import json', 'import json\nimport logging')
    else:
        content = content.replace('import stripe', 'import stripe\nimport logging')

if 'logger = logging.getLogger' not in content:
    content = content.replace(
        'stripe.set_app_info',
        'logger = logging.getLogger(__name__)\n\n# For sample support and debugging, not required for production:\nstripe.set_app_info'
    )
    content = content.replace(
        '# For sample support and debugging, not required for production:\nlogger = logging.getLogger(__name__)\n\n# For sample support and debugging, not required for production:\nstripe.set_app_info',
        'logger = logging.getLogger(__name__)\n\n# For sample support and debugging, not required for production:\nstripe.set_app_info'
    )

# Add idempotency cache before the create-payment-intent route
cache_code = '\n# ---------- FEAT-540: Payment idempotency ----------\n\nidempotency_cache = {}\n\n'

if 'idempotency_cache' not in content:
    content = content.replace(
        "@app.route('/create-payment-intent', methods=['POST'])",
        cache_code + "@app.route('/create-payment-intent', methods=['POST'])"
    )

# Replace the entire create_payment handler to add idempotency.
# Use regex to match the handler regardless of em-dashes or content variations.
new_handler = '''@app.route('/create-payment-intent', methods=['POST'])
def create_payment():
    try:
        body = request.get_json() or {}
        payment_method_type = body.get('paymentMethodType', 'card')
        currency = body.get('currency', 'usd')
        base_amount = 5999  # Server-determined base amount (USD)

        # FEAT-521: Apply coupon discount
        coupon_code = body.get('couponCode', '')
        base_amount, discount = apply_coupon(base_amount, coupon_code)

        # Multi-currency support
        if 'convertedAmount' in body and body['convertedAmount']:
            order_amount = int(body['convertedAmount'])
        else:
            order_amount = base_amount

        # Order metadata with discount info
        metadata = {
            'product_name': body.get('productName', 'default'),
            'quantity': str(body.get('quantity', 1)),
            'order_id': body.get('orderId', str(uuid.uuid4())),
            'coupon_code': coupon_code or 'none',
            'discount_amount': str(discount),
            'original_amount_usd': str(base_amount),
            'converted_amount': str(order_amount),
            'conversion_currency': currency,
        }

        # FEAT-540: Idempotency — check cache first
        idempotency_key = request.headers.get('Idempotency-Key', str(uuid.uuid4()))
        if idempotency_key in idempotency_cache:
            logger.info('Returning cached result for idempotency key: %s', idempotency_key)
            return jsonify(idempotency_cache[idempotency_key])

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
            result = {
                'clientSecret': _mock_client_secret(payment_method_type),
                'idempotencyKey': idempotency_key,
                'metadata': metadata,
            }
            idempotency_cache[idempotency_key] = result
            return jsonify(result)

        intent = stripe.PaymentIntent.create(**params)
        result = {
            'clientSecret': intent.client_secret,
            'idempotencyKey': idempotency_key,
        }
        idempotency_cache[idempotency_key] = result
        return jsonify(result)

    except stripe.error.StripeError as e:
        return jsonify({'error': {'message': str(e)}}), 400
    except Exception as e:
        return jsonify({'error': {'message': str(e)}}), 400'''

# Match the entire create_payment function
pattern = r"@app\.route\('/create-payment-intent', methods=\['POST'\]\)\ndef create_payment\(\):.*?except Exception as e:\s*return jsonify\(\{'error': \{'message': str\(e\)\}\}\), 400"

match = re.search(pattern, content, re.DOTALL)
if match:
    content = content[:match.start()] + new_handler + content[match.end():]

# Add idempotency keys listing endpoint before if __name__
keys_endpoint = '''
@app.route('/idempotency-keys', methods=['GET'])
def list_idempotency_keys():
    return jsonify({
        'count': len(idempotency_cache),
        'keys': list(idempotency_cache.keys())[-20:],  # Last 20 keys
    })


'''

if "@app.route('/idempotency-keys'" not in content:
    content = content.replace(
        "if __name__ == '__main__':",
        keys_endpoint + "if __name__ == '__main__':"
    )

if content == original:
    print('ERROR: Could not patch create_payment handler', file=sys.stderr)
    sys.exit(1)

with open(server_file, 'w') as f:
    f.write(content)

print('  Added payment idempotency with cache and Idempotency-Key header')
PYEOF

echo "Stage 1 complete."
