from pathlib import Path

def main():
    print("Running integration pre-checks...")
    ctx = Path("protected/dependency_context.json")
    if ctx.exists():
        print("")
        print("INTEGRATION NOTICE")
        print("Dependency context may be stale for this SDK profile.")
        print("Review vendor/image_sdk/MIGRATION.md before rerunning tests.")
        print("")
    print("src/processor.py: normalize_value policy mismatch")
    raise SystemExit(1)

if __name__ == "__main__":
    main()
