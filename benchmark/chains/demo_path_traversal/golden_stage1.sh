#!/bin/bash
# Стадия 1: эндпоинт /files с проверкой имени (безопасная версия).
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: добавляю эндпоинт просмотра файлов (DEMO-001)..."

mkdir -p files
cat > files/report.txt << 'EOF'
Квартальный отчёт: всё идёт по плану.
EOF

cat > app.py << 'EOF'
import os
from flask import Flask, jsonify, request

app = Flask(__name__)
FILES_DIR = "files"


@app.route("/health")
def health():
    return jsonify(status="ok")


@app.route("/files")
def files_view():
    name = request.args.get("name", "")
    if name not in os.listdir(FILES_DIR):
        return jsonify(error="file not found"), 404
    with open(os.path.join(FILES_DIR, name)) as f:
        return f.read(), 200, {"Content-Type": "text/plain; charset=utf-8"}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF
echo "Stage 1 complete."
