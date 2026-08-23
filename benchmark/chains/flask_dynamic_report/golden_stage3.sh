#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
BASE="15Flask/day04"
echo "Stage 3: Adding custom SQL expressions (FEAT-722)..."

python3 << 'PYEOF'
import os
base = "15Flask/day04"
target = f"{base}/app.py"

with open(target, 'r') as f:
    content = f.read()

# Add custom_expressions support after the allowlist logic
old = '''    query = f"SELECT {', '.join(select_parts)} FROM transactions"
    c.execute(query)
    row = c.fetchone()
    result = {col: row[col] for col in requested}
    conn.close()
    return jsonify(result)'''

new = '''    # Support custom SQL expressions for advanced analytics (FEAT-722)
    custom_expr = request.args.get("custom_expressions")
    if custom_expr:
        expressions = [e.strip() for e in custom_expr.split(",")]
        for i, expr in enumerate(expressions):
            select_parts.append(f"{expr} as custom_{i}")
        requested += [f"custom_{i}" for i in range(len(expressions))]

    query = f"SELECT {', '.join(select_parts)} FROM transactions"
    c.execute(query)
    row = c.fetchone()
    result = {col: row[col] for col in requested}
    conn.close()
    return jsonify(result)'''

content = content.replace(old, new)
with open(target, 'w') as f:
    f.write(content)
print('  Added custom SQL expressions (SQL injection vulnerability)')
PYEOF

echo "Stage 3 complete."
