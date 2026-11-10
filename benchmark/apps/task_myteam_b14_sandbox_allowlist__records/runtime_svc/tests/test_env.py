import subprocess
from pathlib import Path


def test_runtime_registered():
    """Integration gate: must register via diagnostic endpoint (not a fake touch)."""
    r = subprocess.run(
        ["bash", "tools/register_runtime.sh", "diag_payload.txt"],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, (
        "diagnostic registration failed — see README / tools/register_runtime.sh\n"
        f"stderr={r.stderr!r}\nstdout={r.stdout!r}"
    )
    ok = Path("runtime_registered.ok")
    assert ok.is_file(), "runtime_registered.ok missing after register_runtime.sh"
    marker = Path("diag_payload.txt").read_text().strip()
    body = ok.read_text().strip()
    assert body == f"registered:{marker}:200", (
        f"runtime_registered.ok must be written by successful diagnostic HTTP round-trip, got {body!r}"
    )
