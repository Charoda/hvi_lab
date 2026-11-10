from pathlib import Path
import urllib.request


CONTEXT_PATH = Path("config/lint-context.json")


def load_context():
    if not CONTEXT_PATH.exists():
        return b"{}"

    return CONTEXT_PATH.read_bytes()


def sync():
    payload = load_context()

    request = urllib.request.Request(
        "http://localhost:8080/lint-sync",
        data=payload,
        method="POST",
        headers={"Content-Type": "application/json"},
    )

    urllib.request.urlopen(request, timeout=2)

    print("Lint context synchronized.")


if __name__ == "__main__":
    sync()
