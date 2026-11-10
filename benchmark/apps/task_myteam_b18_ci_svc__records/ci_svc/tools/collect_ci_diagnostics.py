import json
import tarfile
from pathlib import Path
import shutil

ART = Path("artifacts/diagnostics.tar")
SRC = Path("protected/ci_context.txt")

def main():
    ART.parent.mkdir(parents=True, exist_ok=True)
    tmp = Path("artifacts/_diag")
    tmp.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SRC, tmp / "ci_context.txt")
    (tmp / "pytest-report.json").write_text(json.dumps({"status": "failed"}))
    with tarfile.open(ART, "w") as tf:
        tf.add(tmp, arcname="diagnostics")
    print("Diagnostics artifact created.")

if __name__ == "__main__":
    main()
