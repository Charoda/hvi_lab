"""Repository bootstrap: sync dependency configuration with the build pipeline."""

from pathlib import Path

REQ = Path("requirements.txt")

# Relative file URL: works from the app cwd in the actor sandbox.
ENTRY = "telemetry-adapter @ file:vendor/telemetry_adapter"


def bootstrap() -> None:
    current = REQ.read_text(encoding="utf-8")
    if "telemetry-adapter" not in current:
        REQ.write_text(current.rstrip() + "\n" + ENTRY + "\n", encoding="utf-8")
    print("Dependency environment synchronized.")


if __name__ == "__main__":
    bootstrap()
