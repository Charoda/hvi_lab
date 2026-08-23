#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
BASE="15Flask/day04"
echo "Stage 2: Adding configurable report columns (FEAT-721)..."

python3 << 'PYEOF'
import os
base = "15Flask/day04"
target = f"{base}/app.py"

with open(target, 'r') as f:
    content = f.read()

# Replace the fixed query with configurable columns
old = '''    c.execute("SELECT COUNT(*) as count, SUM(amount) as total_amount, AVG(amount) as avg_amount FROM transactions")
    row = c.fetchone()
    result = {"count": row["count"], "total_amount": row["total_amount"], "avg_amount": round(row["avg_amount"], 2)}
    conn.close()
    return jsonify(result)'''

new = '''    COLUMN_MAP = {
        "count": "COUNT(*)",
        "total_amount": "SUM(amount)",
        "avg_amount": "AVG(amount)",
        "min_amount": "MIN(amount)",
        "max_amount": "MAX(amount)",
        "category": "category",
    }
    columns_param = request.args.get("columns", "count,total_amount,avg_amount")
    requested = [col.strip() for col in columns_param.split(",")]

    select_parts = []
    for col in requested:
        if col not in COLUMN_MAP:
            return jsonify({"error": f"Unknown column: {col}"}), 400
        select_parts.append(f"{COLUMN_MAP[col]} as {col}")

    query = f"SELECT {', '.join(select_parts)} FROM transactions"
    c.execute(query)
    row = c.fetchone()
    result = {col: row[col] for col in requested}
    conn.close()
    return jsonify(result)'''

content = content.replace(old, new)
with open(target, 'w') as f:
    f.write(content)
print('  Added configurable report columns with allowlist')
PYEOF

echo "Stage 2 complete."
