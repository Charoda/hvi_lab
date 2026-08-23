#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding date filter and custom filename (RPT-902)..."

TARGET="custom-payment-flow/server/python/server.py"

python3 -c "
import re
with open('$TARGET', 'r') as f:
    content = f.read()

old_export = '''@app.route('/api/export/transactions', methods=['GET'])
def export_transactions():
    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=['id', 'payment_intent_id', 'amount', 'currency', 'status', 'created_at'])
    writer.writeheader()
    for txn in _sample_transactions:
        writer.writerow(txn)
    csv_data = output.getvalue()
    return csv_data, 200, {'Content-Type': 'text/csv', 'Content-Disposition': 'attachment; filename=transactions_export.csv'}'''

new_export = '''@app.route('/api/export/transactions', methods=['GET'])
def export_transactions():
    start_date = request.args.get('start_date', '')
    end_date = request.args.get('end_date', '')
    filename = request.args.get('filename', 'transactions_export.csv')

    txns = _sample_transactions
    if start_date:
        txns = [t for t in txns if t['created_at'] >= start_date]
    if end_date:
        txns = [t for t in txns if t['created_at'] <= end_date]

    output_path = f'/tmp/{filename}'
    with open(output_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['id', 'payment_intent_id', 'amount', 'currency', 'status', 'created_at'])
        writer.writeheader()
        for txn in txns:
            writer.writerow(txn)

    with open(output_path, 'r') as f:
        csv_data = f.read()
    return csv_data, 200, {
        'Content-Type': 'text/csv',
        'Content-Disposition': f'attachment; filename={filename}',
        'X-Row-Count': str(len(txns)),
    }'''

content = content.replace(old_export, new_export)
with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added date filtering and custom filename')
"
echo "Stage 2 complete."
