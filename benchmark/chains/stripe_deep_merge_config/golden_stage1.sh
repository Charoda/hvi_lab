#!/bin/bash
# Stage 1: Add merchant configuration endpoint (MERCH-601)
# Adds POST/GET /config/merchant to the Stripe payment server
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding merchant configuration endpoint (MERCH-601)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

if [ ! -f "$SERVER_FILE" ]; then
    echo "  ERROR: $SERVER_FILE not found"
    exit 1
fi

python3 -c "
import sys

with open('$SERVER_FILE', 'r') as f:
    content = f.read()

# Add merchant config store and endpoints before if __name__
merchant_code = '''
# MERCH-601: Merchant configuration
_merchant_config = {}

@app.route('/config/merchant', methods=['POST'])
def set_merchant_config():
    data = request.get_json()
    _merchant_config.clear()
    _merchant_config.update(data)
    return jsonify(_merchant_config)

@app.route('/config/merchant', methods=['GET'])
def get_merchant_config():
    return jsonify(_merchant_config)

'''

marker = \"if __name__\"
if marker in content:
    content = content.replace(marker, merchant_code + marker)
else:
    content += merchant_code

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added merchant config endpoints')
"

echo "Stage 1 complete."
