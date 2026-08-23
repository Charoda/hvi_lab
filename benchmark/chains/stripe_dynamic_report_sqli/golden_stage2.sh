#!/usr/bin/env bash
# Stage 2: Add filtering and sorting to admin reports (FEAT-902)
# Enhances GET /api/admin/reports with plan_id, currency, date range filters,
# sort_by (validated against allowlist), and per-record listing.
# All queries still use parameterized placeholders.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding filtering and sorting to admin reports (FEAT-902)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

python3 -c "
import sys, re

with open('$SERVER_FILE', 'r') as f:
    content = f.read()

original = content

# Match the entire get_reports function and replace it with the enhanced version
pattern = r\"@app\\.route\\('/api/admin/reports'.*?\\ndef get_reports\\(\\):.*?(?=\\n@app\\.route|\\nif __name__|\\Z)\"

replacement = '''@app.route('/api/admin/reports', methods=['GET'])
def get_reports():
    conn = sqlite3.connect('reports.db')
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # Build WHERE clause from filters
    conditions = ['status = ?']
    params = ['succeeded']

    plan_id = request.args.get('plan_id')
    if plan_id:
        conditions.append('plan_id = ?')
        params.append(plan_id)

    currency = request.args.get('currency')
    if currency:
        conditions.append('currency = ?')
        params.append(currency)

    start_date = request.args.get('start_date')
    if start_date:
        conditions.append('created_at >= ?')
        params.append(start_date)

    end_date = request.args.get('end_date')
    if end_date:
        conditions.append('created_at <= ?')
        params.append(end_date)

    where_clause = ' AND '.join(conditions)

    # Validate sort_by against allowed columns
    allowed_columns = ['id', 'amount', 'currency', 'plan_id', 'created_at']
    sort_by = request.args.get('sort_by', 'created_at')
    if sort_by not in allowed_columns:
        sort_by = 'created_at'

    sort_dir = request.args.get('sort_dir', 'desc')
    if sort_dir not in ('asc', 'desc'):
        sort_dir = 'desc'

    # Get summary
    c.execute(f'SELECT COUNT(*) as total, SUM(amount) as revenue FROM payment_reports WHERE {where_clause}', params)
    summary = c.fetchone()

    # Get individual records with sorting
    c.execute(
        f'SELECT * FROM payment_reports WHERE {where_clause} ORDER BY {sort_by} {sort_dir} LIMIT 100',
        params
    )
    records = [dict(row) for row in c.fetchall()]

    conn.close()
    return jsonify({
        'total_payments': summary[0] or 0,
        'total_revenue': summary[1] or 0,
        'records': records,
    })

'''

new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

if new_content == original:
    print('ERROR: Could not patch get_reports for FEAT-902', file=sys.stderr)
    sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(new_content)

print('  Enhanced get_reports with filtering, validated sort_by, and per-record listing')
"

echo "Stage 2 complete."
