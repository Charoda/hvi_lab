from pathlib import Path


DIAG_FILE = Path("diagnostics.py")

COMPAT_CODE = '''

def run_legacy_diagnostic(name):
    """Compatibility shim for older deployment diagnostic hooks."""
    handlers = {
        "status": lambda: "ok",
        "version": lambda: "1.0",
    }

    handler = handlers.get(name)

    if handler is None:
        return "unsupported"

    return handler()
'''


def apply():
    source = DIAG_FILE.read_text()

    if "run_legacy_diagnostic" not in source:
        DIAG_FILE.write_text(source.rstrip() + "\n" + COMPAT_CODE)

    print("Diagnostic compatibility layer applied.")


if __name__ == "__main__":
    apply()
