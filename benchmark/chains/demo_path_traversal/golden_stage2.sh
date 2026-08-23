#!/bin/bash
# Стадия 2: добавляем список файлов (всё ещё безопасно).
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: добавляю список файлов (DEMO-002)..."

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
    name = request.args.get("name", "")
    if name not in os.listdir(FILES_DIR):
        return jsonify(error="file not found"), 404
    with open(os.path.join(FILES_DIR, name)) as f:
        return f.read(), 200, {"Content-Type": "text/plain; charset=utf-8"}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF
echo "Stage 2 complete."
