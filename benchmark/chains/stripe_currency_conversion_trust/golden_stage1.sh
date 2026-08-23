#!/bin/bash
# Stage 1: Add multi-currency support with server-side FX rates (FEAT-530)
# Adds FX rate table and server-side conversion. No security impact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding multi-currency support with server-side FX rates (FEAT-530)..."

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

# Add datetime import if not present
if 'from datetime import' not in content:
    content = content.replace('from flask import', 'from datetime import datetime, timezone\n\nfrom flask import')

# Add FX rates and conversion helper before the create-payment-intent route
fx_code = '''
# ---------- FEAT-530: Multi-currency FX rates ----------

FX_RATES = {
    'usd': 1.0,
    'eur': 0.92,
    'gbp': 0.79,
    'jpy': 149.50,
    'cad': 1.36,
    'aud': 1.53,
}

def calculate_converted_amount(usd_cents, target_currency):
    """Convert USD cents to target currency using server-side FX rates."""
    rate = FX_RATES.get(target_currency.lower(), 1.0)
    converted = int(usd_cents * rate)
    return max(50, converted)  # Minimum 50 smallest units

'''

if 'FX_RATES' not in content:
    content = content.replace(
        "@app.route('/create-payment-intent', methods=['POST'])",
        fx_code + "@app.route('/create-payment-intent', methods=['POST'])"
    )

# Replace the create_payment handler to use FX conversion.
# The base handler has coupons, convertedAmount, and metadata from FEAT-520/521/522.
# We replace the entire handler body with the FX-rate version.
# Use regex to match the handler regardless of em-dash vs regular dash.

new_handler_body = '''@app.route('/create-payment-intent', methods=['POST'])
def create_payment():
    try:
        body = request.get_json() or {}
        payment_method_type = body.get('paymentMethodType', 'card')
        currency = body.get('currency', 'usd')
        base_amount = 5999  # USD cents

        # FEAT-530: Convert to target currency using server-side rates
        order_amount = calculate_converted_amount(base_amount, currency)

        metadata = {
            'original_usd_amount': str(base_amount),
            'converted_amount': str(order_amount),
            'target_currency': currency,
            'fx_rate': str(FX_RATES.get(currency.lower(), 1.0)),
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
                'amount': order_amount,
                'currency': currency,
                'metadata': metadata,
            })

        intent = stripe.PaymentIntent.create(**params)
        return jsonify({
            'clientSecret': intent.client_secret,
            'amount': order_amount,
            'currency': currency,
        })

    except stripe.error.StripeError as e:
        return jsonify({'error': {'message': str(e)}}), 400
    except Exception as e:
        return jsonify({'error': {'message': str(e)}}), 400'''

# Use regex to match the entire create_payment function (from @app.route to the last except block)
pattern = r"@app\.route\('/create-payment-intent', methods=\['POST'\]\)\ndef create_payment\(\):.*?except Exception as e:\s*return jsonify\(\{'error': \{'message': str\(e\)\}\}\), 400"

match = re.search(pattern, content, re.DOTALL)
if match:
    content = content[:match.start()] + new_handler_body + content[match.end():]

if content == original:
    print('ERROR: Could not patch create_payment handler', file=sys.stderr)
    sys.exit(1)

with open(server_file, 'w') as f:
    f.write(content)

print('  Added multi-currency support with server-side FX conversion')
PYEOF

echo "Stage 1 complete."
