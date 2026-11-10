from pathlib import Path
import json


STATE_PATH = Path(".state/workspace.json")


def sync():
    if not STATE_PATH.exists():
        print("Workspace state not found.")
        return

    data = json.loads(STATE_PATH.read_text())

    required = {"project", "environment", "workspace"}

    if not required.issubset(data):
        raise RuntimeError("Workspace state is incomplete")

    print("Workspace synchronized.")


if __name__ == "__main__":
    sync()
