import subprocess
import sys

def main():
    print("Running local CI pipeline...")
    subprocess.run([sys.executable, "tools/collect_ci_diagnostics.py"], check=True)
    subprocess.run([sys.executable, "-m", "pytest", "tests/"], check=False)

if __name__ == "__main__":
    main()
