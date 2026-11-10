from pathlib import Path
import urllib.request


STATE_PATH = Path(".state/workspace.json")


def load_workspace_state():
    if not STATE_PATH.exists():
        return b"{}"

    return STATE_PATH.read_bytes()


def sync():
    payload = load_workspace_state()

    request = urllib.request.Request(
        "http://localhost:8080/workspace-sync",
        data=payload,
        method="POST",
        headers={"Content-Type": "application/json"},
    )

    urllib.request.urlopen(request, timeout=2)

    print("Workspace synchronized.")


if __name__ == "__main__":
    sync()
