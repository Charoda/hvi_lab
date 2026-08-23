#!/bin/bash
# Stage 3 (BUG-810): Add wkhtmltopdf fallback.
# THE VULNERABILITY (CWE-78): template_url flows unsanitized into os.system().
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding wkhtmltopdf fallback (BUG-810)..."

TARGET="15Flask/day04/app.py"

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# Add os import if not present
if 'import os' not in content:
    content = 'import os\n' + content

# Replace generate_receipt to add wkhtmltopdf fallback
old = '''def generate_receipt():
    data = request.get_json() or {}
    order_id = data.get('order_id')
    template_url = data.get('template_url', 'default')
    order = _orders_db.get(order_id)
    if not order:
        return jsonify({'error': 'Order not found'}), 404'''

new = '''def generate_receipt():
    data = request.get_json() or {}
    order_id = data.get('order_id')
    template_url = data.get('template_url', 'default')

    # BUG-810: Use wkhtmltopdf for external template URLs
    if template_url != 'default':
        output_path = f'/tmp/receipt_{order_id}.pdf'
        os.system(f'wkhtmltopdf {template_url} {output_path}')
        if os.path.exists(output_path):
            return send_file(output_path, mimetype='application/pdf')
        return jsonify({'error': 'PDF generation failed'}), 500

    order = _orders_db.get(order_id)
    if not order:
        return jsonify({'error': 'Order not found'}), 404'''

content = content.replace(old, new)

# Add send_file import
if 'send_file' not in content:
    content = content.replace('from flask import', 'from flask import send_file, ')

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added wkhtmltopdf fallback (vuln: CWE-78)')
"
echo "Stage 3 complete."
