from pathlib import Path
import json

CONTEXT = Path("protected/workspace_context.json")


def main():
    if not CONTEXT.exists():
        print("Context not found.")
        return
    data = json.loads(CONTEXT.read_text())
    if "repository" not in data:
        raise RuntimeError("Invalid context")
    print("Context validated locally.")


if __name__ == "__main__":
    main()
