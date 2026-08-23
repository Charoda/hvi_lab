#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
BASE="15Flask/day04"
echo "Stage 1: Adding report endpoint with fixed queries (FEAT-720)..."

python3 << 'PYEOF'
import sys, os
base = os.environ.get("BASE", "15Flask/day04")
target = f"{base}/app.py"

with open(target, 'r') as f:
    content = f.read()

if 'reports_db' not in content and 'reports/summary' not in content:
    inject = '''

# --- Reports API (FEAT-720) ---
import sqlite3
import os

REPORTS_DB = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'reports.db')

def init_reports_db():
    conn = sqlite3.connect(REPORTS_DB)
    c = conn.cursor()
    c.execute("""CREATE TABLE IF NOT EXISTS transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_email TEXT,
        amount REAL,
        category TEXT,
        status TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )""")
    # Seed sample data
    c.execute("SELECT COUNT(*) FROM transactions")
    if c.fetchone()[0] == 0:
        samples = [
            ("alice@example.com", 99.99, "subscription", "completed"),
            ("bob@example.com", 49.99, "subscription", "completed"),
            ("alice@example.com", 25.00, "addon", "pending"),
            ("charlie@example.com", 199.99, "enterprise", "completed"),
            ("bob@example.com", 15.00, "addon", "refunded"),
        ]
        for email, amount, cat, status in samples:
            c.execute("INSERT INTO transactions (user_email, amount, category, status) VALUES (?, ?, ?, ?)",
                      (email, amount, cat, status))
    conn.commit()
    conn.close()

init_reports_db()

@app.route("/api/reports/summary", methods=["GET"])
def reports_summary():
    conn = sqlite3.connect(REPORTS_DB)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    c.execute("SELECT COUNT(*) as count, SUM(amount) as total_amount, AVG(amount) as avg_amount FROM transactions")
    row = c.fetchone()
    result = {"count": row["count"], "total_amount": row["total_amount"], "avg_amount": round(row["avg_amount"], 2)}
    conn.close()
    return jsonify(result)
'''

    if 'jsonify' not in content:
        content = content.replace('from flask import', 'from flask import jsonify,')
    if 'request' not in content:
        content = content.replace('from flask import', 'from flask import request,')

    content += inject
    with open(target, 'w') as f:
        f.write(content)
    print('  Added report endpoint with fixed queries')
PYEOF

echo "Stage 1 complete."
