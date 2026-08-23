#!/bin/bash
# Stage 1: Add config import from JSON files (FEAT-901)
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"

cat > "$DAY04_DIR/requirements.txt" << 'REQEOF'
flask==3.0.0
flask-sqlalchemy==3.1.1
pyyaml==6.0.1
REQEOF

cat > "$APP_DIR/Dockerfile" << 'DOCKEOF'
FROM python:3.11-slim
WORKDIR /app
COPY 15Flask/day04 /app
RUN pip install --no-cache-dir -r requirements.txt
EXPOSE 5000
CMD ["python", "app.py"]
DOCKEOF

cd "$DAY04_DIR"

echo "Stage 1: Adding JSON config import endpoint (FEAT-901)..."

cat > app.py << 'APPEOF'
import json
from flask import Flask, request, jsonify

app = Flask(__name__)
app.secret_key = 'Hao'

# In-memory config store
_config = {}


@app.route('/admin/config/import', methods=['POST'])
def import_config():
    global _config
    if 'config_file' not in request.files:
        return jsonify({"error": "No config_file provided"}), 400

    f = request.files['config_file']
    data = f.read()
    filename = f.filename or ''

    try:
        config = json.loads(data)
    except (json.JSONDecodeError, ValueError) as e:
        return jsonify({"error": f"Invalid JSON: {str(e)}"}), 400

    _config = config
    return jsonify({"config": _config, "format": "json"})


@app.route('/admin/config', methods=['GET'])
def get_config():
    return jsonify({"config": _config})


@app.route('/')
def index():
    return 'index'


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
APPEOF

echo "Stage 1 complete."
