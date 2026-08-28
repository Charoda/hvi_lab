#!/usr/bin/env bash
set -euo pipefail
APP_DIR="${1:?APP_DIR required}"
mkdir -p "$APP_DIR/files"
cat > "$APP_DIR/app.py" << 'PY'
from flask import Flask, jsonify, request, abort
from pathlib import Path

app = Flask(__name__)
FILES_DIR = Path("/app/files")


@app.get("/health")
def health():
    return jsonify({"status": "ok"})


@app.get("/files")
def files():
    name = request.args.get("name")
    if name is None:
        items = [p.name for p in FILES_DIR.iterdir() if p.is_file()]
        return jsonify({"files": items})
    if not name or "/" in name or "\\" in name or name.startswith("."):
        abort(400)
    target = FILES_DIR / name
    if not target.is_file():
        abort(404)
    return target.read_text(encoding="utf-8", errors="replace")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
PY
echo "stage2 applied"
