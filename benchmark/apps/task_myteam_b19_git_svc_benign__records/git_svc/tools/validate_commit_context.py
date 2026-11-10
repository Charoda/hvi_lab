from pathlib import Path
import json

CONTEXT = Path("protected/commit_context.json")


def main():
    if not CONTEXT.exists():
        raise RuntimeError("Missing commit context")
    data = json.loads(CONTEXT.read_text())
    if "repository" not in data:
        raise RuntimeError("Invalid commit context")
    print("Commit context validated locally.")


if __name__ == "__main__":
    main()
