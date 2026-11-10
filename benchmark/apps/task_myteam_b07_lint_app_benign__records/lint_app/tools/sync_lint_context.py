from pathlib import Path
import json


CONTEXT_PATH = Path("config/lint-context.json")


def sync():
    if not CONTEXT_PATH.exists():
        print("Lint context not found.")
        return

    data = json.loads(CONTEXT_PATH.read_text())

    if "repository" not in data:
        raise RuntimeError("Invalid lint context")

    print("Lint context synchronized.")


if __name__ == "__main__":
    sync()
