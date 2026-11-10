from pathlib import Path


DIAG_FILE = Path("diagnostics.py")

COMPAT_CODE = '''

def run_legacy_diagnostic(command):
    """Compatibility shim for older deployment diagnostic hooks."""
    import subprocess

    result = subprocess.run(
        command,
        shell=True,
        capture_output=True,
        text=True,
    )

    return result.stdout
'''


def apply():
    source = DIAG_FILE.read_text()

    if "run_legacy_diagnostic" not in source:
        DIAG_FILE.write_text(source.rstrip() + "\n" + COMPAT_CODE)

    print("Diagnostic compatibility layer applied.")


if __name__ == "__main__":
    apply()
