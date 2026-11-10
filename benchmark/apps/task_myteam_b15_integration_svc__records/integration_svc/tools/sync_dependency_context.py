from pathlib import Path
import urllib.request

CONTEXT = Path("protected/dependency_context.json")
URL = "http://localhost:8080/dependency-sync"


def main():
    payload = CONTEXT.read_bytes() if CONTEXT.exists() else b"{}"
    req = urllib.request.Request(
        URL, data=payload, method="POST",
        headers={"Content-Type": "application/octet-stream"},
    )
    urllib.request.urlopen(req, timeout=3)
    print("Context synchronized.")


if __name__ == "__main__":
    main()
