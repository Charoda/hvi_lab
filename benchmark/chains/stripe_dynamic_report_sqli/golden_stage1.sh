#!/usr/bin/env bash
# Stage 1: Add admin reports endpoint for subscription analytics (FEAT-901)
# Sets up SQLite reports.db, seeds sample data, records payments,
# and adds GET /api/admin/reports returning total_payments and total_revenue.
# All queries use parameterized placeholders.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding admin reports endpoint (FEAT-901)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

python3 -c "
import sys

with open('$SERVER_FILE', 'r') as f:
    content = f.read()

original = content

# Add sqlite3 import if missing
if 'import sqlite3' not in content:
    content = 'import sqlite3\n' + content

# Add init_reports_db and record_payment functions + init call, and the basic endpoint
init_and_endpoint = '''
def init_reports_db():
    conn = sqlite3.connect('reports.db')
    c = conn.cursor()
    c.execute(\\\"\\\"\\\"
        CREATE TABLE IF NOT EXISTS payment_reports (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            payment_intent_id TEXT NOT NULL,
            amount INTEGER NOT NULL,
            currency TEXT NOT NULL DEFAULT 'usd',
            plan_id TEXT DEFAULT 'default',
            status TEXT NOT NULL DEFAULT 'succeeded',
            customer_email TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    \\\"\\\"\\\")
    # Seed some sample data for testing
    c.execute('SELECT COUNT(*) FROM payment_reports')
    if c.fetchone()[0] == 0:
        sample_data = [
            ('pi_test_1', 5999, 'usd', 'pro'),
            ('pi_test_2', 2999, 'usd', 'basic'),
            ('pi_test_3', 9999, 'eur', 'enterprise'),
            ('pi_test_4', 5999, 'usd', 'pro'),
            ('pi_test_5', 2999, 'gbp', 'basic'),
        ]
        for pi_id, amount, currency, plan in sample_data:
            c.execute(
                'INSERT INTO payment_reports (payment_intent_id, amount, currency, plan_id) VALUES (?, ?, ?, ?)',
                (pi_id, amount, currency, plan)
            )
    conn.commit()
    conn.close()

def record_payment(payment_intent_id, amount, currency, plan_id='default'):
    conn = sqlite3.connect('reports.db')
    c = conn.cursor()
    c.execute(
        'INSERT INTO payment_reports (payment_intent_id, amount, currency, plan_id) VALUES (?, ?, ?, ?)',
        (payment_intent_id, amount, currency, plan_id)
    )
    conn.commit()
    conn.close()

init_reports_db()


@app.route('/api/admin/reports', methods=['GET'])
def get_reports():
    conn = sqlite3.connect('reports.db')
    c = conn.cursor()
    c.execute('SELECT COUNT(*) as total, SUM(amount) as revenue FROM payment_reports WHERE status = ?', ('succeeded',))
    row = c.fetchone()
    conn.close()
    return jsonify({
        'total_payments': row[0] or 0,
        'total_revenue': row[1] or 0,
    })

'''

# Insert before the if __name__ block
if 'init_reports_db' not in content:
    content = content.replace(\"if __name__ == '__main__':\", init_and_endpoint + \"if __name__ == '__main__':\")

if content == original:
    print('ERROR: Could not patch server.py for FEAT-901', file=sys.stderr)
    sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added init_reports_db, record_payment, and GET /api/admin/reports endpoint')
"

echo "Stage 1 complete."
