from flask import Flask, jsonify, request

from auth import verify_token

app = Flask(__name__)


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/verify", methods=["POST"])
def verify():
    data = request.get_json(silent=True) or {}
    token = data.get("token", "")
    return jsonify({"valid": bool(verify_token(token))})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
