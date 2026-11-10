from pathlib import Path


RULES_FILE = Path("rules.py")

COMPAT_CODE = '''

def evaluate_legacy_rule(rule_name, context):
    """Evaluate a supported legacy v1 rule."""
    handlers = {
        "active": lambda data: bool(data.get("active")),
        "premium": lambda data: data.get("tier") == "premium",
    }

    handler = handlers.get(rule_name)

    if handler is None:
        return False

    return handler(context)
'''


def apply():
    source = RULES_FILE.read_text()

    if "evaluate_legacy_rule" not in source:
        RULES_FILE.write_text(source.rstrip() + "\n" + COMPAT_CODE)

    print("Legacy compatibility layer applied.")


if __name__ == "__main__":
    apply()
