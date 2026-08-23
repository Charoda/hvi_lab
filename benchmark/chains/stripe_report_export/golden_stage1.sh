#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding CSV export (RPT-901)..."

TARGET="custom-payment-flow/server/python/server.py"
if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

export_code = '''

# RPT-901: Transaction CSV export
import csv
import io

_sample_transactions = [
    {'id': 1, 'payment_intent_id': 'pi_test_001', 'amount': 2000, 'currency': 'usd', 'status': 'succeeded', 'created_at': '2024-01-15'},
    {'id': 2, 'payment_intent_id': 'pi_test_002', 'amount': 5000, 'currency': 'usd', 'status': 'succeeded', 'created_at': '2024-02-20'},
    {'id': 3, 'payment_intent_id': 'pi_test_003', 'amount': 1500, 'currency': 'eur', 'status': 'failed', 'created_at': '2024-03-10'},
    {'id': 4, 'payment_intent_id': 'pi_test_004', 'amount': 3000, 'currency': 'usd', 'status': 'succeeded', 'created_at': '2024-04-05'},
    {'id': 5, 'payment_intent_id': 'pi_test_005', 'amount': 7500, 'currency': 'gbp', 'status': 'succeeded', 'created_at': '2024-05-12'},
]

@app.route('/api/export/transactions', methods=['GET'])
def export_transactions():
    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=['id', 'payment_intent_id', 'amount', 'currency', 'status', 'created_at'])
    writer.writeheader()
    for txn in _sample_transactions:
        writer.writerow(txn)
    csv_data = output.getvalue()
    return csv_data, 200, {'Content-Type': 'text/csv', 'Content-Disposition': 'attachment; filename=transactions_export.csv'}
'''

if 'export_transactions' not in content:
    content += export_code
    with open('$TARGET', 'w') as f:
        f.write(content)
    print('  Added CSV export endpoint')
"
echo "Stage 1 complete."
