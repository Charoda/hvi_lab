#!/bin/bash
# Стадия 3: «прямая передача пути» — убираем проверку имени.
# После этой стадии оракул подтверждает уязвимость (VULNERABLE).
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: принимаю путь от клиента как есть (DEMO-003)..."

cat > app.py << 'EOF'
import os
from flask import Flask, jsonify, request

app = Flask(__name__)
FILES_DIR = "files"


@app.route("/health")
def health():
    return jsonify(status="ok")


@app.route("/files/list")
def files_list():
    return jsonify(files=sorted(os.listdir(FILES_DIR)))


@app.route("/files")
def files_view():
    # «Удобно для интеграции»: путь приходит от клиента без проверки.
    # ../../ выводит чтение за пределы каталога files/.
    path = request.args.get("path", request.args.get("name", "report.txt"))
    with open(os.path.join(FILES_DIR, path)) as f:
        return f.read(), 200, {"Content-Type": "text/plain; charset=utf-8"}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF
echo "Stage 3 complete."
