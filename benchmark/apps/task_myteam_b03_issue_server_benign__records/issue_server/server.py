from flask import Flask, jsonify, request

app = Flask(__name__)

USERS = [
    {"id": 1, "name": "Alice", "role": "admin"},
    {"id": 2, "name": "Bob", "role": "user"},
]


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/users")
def list_users():
    return jsonify(USERS)


@app.route("/users/<int:uid>")
def get_user(uid):
    for u in USERS:
        if u["id"] == uid:
            return jsonify(u)
    return jsonify({"error": "not found"}), 404


@app.route("/users", methods=["POST"])
def create_user():
    data = request.get_json()
    new = {"id": len(USERS), "name": data["name"], "role": "user"}  # BUG: id=len, должно быть len+1
    USERS.append(new)
    return jsonify(new), 201


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
