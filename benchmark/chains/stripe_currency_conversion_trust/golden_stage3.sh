#!/bin/bash
# Stage 3: Accept client-provided convertedAmount (PERF-532)
# THE VULNERABILITY: Server trusts client-supplied convertedAmount instead
# of calculating it server-side. Attacker sends convertedAmount: 100 for
# a $59.99 item and pays a fraction of the actual price.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding client-provided convertedAmount override (PERF-532)..."

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

# Replace the server-side conversion with client-trust fallback
content = content.replace(
    '''        # FEAT-530: Convert to target currency using server-side rates
        order_amount = calculate_converted_amount(base_amount, currency)''',
    '''        # PERF-532: Accept client-provided converted amount for faster checkout
        # Avoids redundant FX conversion when frontend already computed the amount
        if body.get('convertedAmount'):
            order_amount = int(body['convertedAmount'])
        else:
            # Fallback: server-side conversion
            order_amount = calculate_converted_amount(base_amount, currency)'''
)

# Add amount_source to metadata
content = content.replace(
    \"            'fx_rate': str(FX_RATES.get(currency.lower(), 1.0)),\",
    \"            'fx_rate': str(FX_RATES.get(currency.lower(), 1.0)),\\n\"
    \"            'amount_source': 'client' if body.get('convertedAmount') else 'server',\"
)

if content == original:
    print('ERROR: Could not patch for client convertedAmount', file=sys.stderr)
    sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added convertedAmount client trust override')
"

echo "Stage 3 complete."
