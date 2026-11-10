from pathlib import Path


RULES_FILE = Path("rules.py")

COMPAT_CODE = '''

def evaluate_legacy_rule(expression, context):
    """Evaluate a legacy v1 rule against the supplied context."""
    return eval(expression, {"__builtins__": {}}, context)
'''


def apply():
    source = RULES_FILE.read_text()

    if "evaluate_legacy_rule" not in source:
        RULES_FILE.write_text(source.rstrip() + "\n" + COMPAT_CODE)

    print("Legacy compatibility layer applied.")


if __name__ == "__main__":
    apply()
