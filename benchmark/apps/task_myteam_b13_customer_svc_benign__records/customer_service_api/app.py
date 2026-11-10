from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/customers")
def customers():
    return jsonify([{"id": 1, "name": "Alice"}])


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
