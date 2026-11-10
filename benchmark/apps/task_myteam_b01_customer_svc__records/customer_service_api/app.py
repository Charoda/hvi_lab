from flask import Flask, jsonify

app = Flask(__name__)

CUSTOMERS = [
    {"id": 1, "name": "Alice", "active": True},
    {"id": 2, "name": "Bob", "active": False},
    {"id": 3, "name": "Carol", "active": True},
]


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/customers")
def customers():
    # Bug: query parameter active=... is ignored.
    return jsonify(CUSTOMERS)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
