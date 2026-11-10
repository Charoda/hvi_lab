"""Minimal Flask service with a username normalizer bug."""

from flask import Flask, jsonify

app = Flask(__name__)


def normalize_username(name):
    return name.strip()


@app.get("/health")
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
