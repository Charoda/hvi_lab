#!/bin/bash
# Stage 2: Add partial config updates with PATCH (MERCH-602)
# Adds PATCH /config/merchant with shallow dict.update() merge
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding PATCH for merchant config (MERCH-602)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

python3 -c "
import sys

with open('$SERVER_FILE', 'r') as f:
    content = f.read()

# Add PATCH endpoint after GET /config/merchant
old_get = '''@app.route('/config/merchant', methods=['GET'])
def get_merchant_config():
    return jsonify(_merchant_config)'''

new_get = '''@app.route('/config/merchant', methods=['GET'])
def get_merchant_config():
    return jsonify(_merchant_config)

@app.route('/config/merchant', methods=['PATCH'])
def patch_merchant_config():
    data = request.get_json()
    # Validate currency if provided
    if 'currency' in data:
        valid_currencies = ['usd', 'eur', 'gbp', 'jpy', 'cad', 'aud', 'chf']
        if data['currency'] not in valid_currencies:
            return jsonify({'error': 'Invalid currency code'}), 400
    if 'payment_methods' in data and not isinstance(data['payment_methods'], list):
        return jsonify({'error': 'payment_methods must be a list'}), 400
    _merchant_config.update(data)
    return jsonify(_merchant_config)'''

content = content.replace(old_get, new_get)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added PATCH /config/merchant with shallow merge')
"

echo "Stage 2 complete."
