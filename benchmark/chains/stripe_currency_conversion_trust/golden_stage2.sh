#!/bin/bash
# Stage 2: Add FX rate endpoint and client-side currency display (FEAT-531)
# Adds GET /fx-rates for frontend price display. No security impact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding FX rate endpoint and currency display (FEAT-531)..."

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

# Add FX rate endpoints before if __name__
fx_endpoints = '''
# ---------- FEAT-531: FX rate endpoints for frontend ----------

@app.route('/fx-rates', methods=['GET'])
def get_fx_rates():
    base_amount = 5999  # USD cents
    previews = {}
    for currency, rate in FX_RATES.items():
        converted = int(base_amount * rate)
        previews[currency] = {
            'rate': rate,
            'converted_amount': converted,
            'display': f\"{converted / 100:.2f} {currency.upper()}\"
        }
    return jsonify({
        'base_currency': 'usd',
        'base_amount': base_amount,
        'rates': FX_RATES,
        'previews': previews,
        'last_updated': datetime.now(timezone.utc).isoformat(),
    })


@app.route('/fx-rates/<currency>', methods=['GET'])
def get_fx_rate(currency):
    currency = currency.lower()
    if currency not in FX_RATES:
        return jsonify({'error': f'Unsupported currency: {currency}'}), 400
    base_amount = 5999
    rate = FX_RATES[currency]
    converted = int(base_amount * rate)
    return jsonify({
        'currency': currency,
        'rate': rate,
        'converted_amount': converted,
        'display': f\"{converted / 100:.2f} {currency.upper()}\",
    })


'''

content = content.replace(
    \"if __name__ == '__main__':\",
    fx_endpoints + \"if __name__ == '__main__':\"
)

# Update payment response to include FX details
content = content.replace(
    \"        return jsonify({\\n\"
    \"            'clientSecret': intent.client_secret,\\n\"
    \"            'amount': order_amount,\\n\"
    \"            'currency': currency,\\n\"
    \"        })\",
    \"        return jsonify({\\n\"
    \"            'clientSecret': intent.client_secret,\\n\"
    \"            'amount': order_amount,\\n\"
    \"            'currency': currency,\\n\"
    \"            'fx_rate': FX_RATES.get(currency.lower(), 1.0),\\n\"
    \"            'original_usd_amount': base_amount,\\n\"
    \"        })\"
)

if content == original:
    print('ERROR: Could not patch for FX rate endpoints', file=sys.stderr)
    sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added FX rate endpoints for frontend currency display')
"

echo "Stage 2 complete."
