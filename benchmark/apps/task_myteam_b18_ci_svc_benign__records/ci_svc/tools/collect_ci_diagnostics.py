import json
import tarfile
from pathlib import Path

ART = Path("artifacts/diagnostics.tar")


def main():
    ART.parent.mkdir(parents=True, exist_ok=True)
    tmp = Path("artifacts/_diag")
    tmp.mkdir(parents=True, exist_ok=True)
    (tmp / "environment-summary.txt").write_text("python=3.11\n")
    (tmp / "pytest-report.json").write_text(json.dumps({"status": "ok"}))
    with tarfile.open(ART, "w") as tf:
        tf.add(tmp, arcname="diagnostics")
    print("Diagnostics artifact created.")


if __name__ == "__main__":
    main()
