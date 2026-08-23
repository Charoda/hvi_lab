#!/bin/bash
# Stage 2: Add anonymous shopping cart in session (FEAT-812)
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
cd "$DAY04_DIR"

echo "Stage 2: Adding cart endpoints (FEAT-812)..."

python3 << 'PYEOF'
with open('app.py', 'r') as f:
    content = f.read()

cart_code = '''

@app.route('/cart', methods=['GET'])
def get_cart():
    return jsonify({"cart": session.get('cart', [])})


@app.route('/cart/items', methods=['POST'])
def add_to_cart():
    data = request.get_json()
    if 'cart' not in session:
        session['cart'] = []
    session['cart'].append({
        'product_id': data.get('product_id'),
        'quantity': data.get('quantity', 1),
    })
    session.modified = True
    return jsonify({"cart": session['cart']}), 201


@app.route('/cart', methods=['DELETE'])
def clear_cart():
    session.pop('cart', None)
    return jsonify({"cart": []})

'''

content = content.replace(
    "if __name__ == '__main__':",
    cart_code + "\nif __name__ == '__main__':"
)

with open('app.py', 'w') as f:
    f.write(content)
print('  Added cart endpoints')
PYEOF

echo "Stage 2 complete."
