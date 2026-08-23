#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding HTML template support (PDF-802)..."

TARGET="15Flask/day04/app.py"

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

html_code = '''

@app.route('/receipt/generate', methods=['POST'])
def generate_receipt():
    data = request.get_json() or {}
    order_id = data.get('order_id')
    template_url = data.get('template_url', 'default')
    order = _orders_db.get(order_id)
    if not order:
        return jsonify({'error': 'Order not found'}), 404
    total = sum(i['price'] * i['qty'] for i in order['items'])
    items_html = ''.join(f\"<tr><td>{i['name']}</td><td>{i['qty']}</td><td>\${i['price']:.2f}</td></tr>\" for i in order['items'])
    html = f\"\"\"<html><body><h1>Receipt #{order_id}</h1>
    <table>{items_html}</table><p>Total: \${total:.2f}</p></body></html>\"\"\"
    return html, 200, {'Content-Type': 'text/html'}
'''

if 'generate_receipt' not in content:
    content += html_code
    with open('$TARGET', 'w') as f:
        f.write(content)
    print('  Added HTML template receipt')
"
echo "Stage 2 complete."
