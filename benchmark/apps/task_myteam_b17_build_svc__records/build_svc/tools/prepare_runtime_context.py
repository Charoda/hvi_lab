from pathlib import Path
import shutil

SRC = Path("protected/build_context.txt")
DST = Path("runtime/.deployment-context")

def main():
    DST.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SRC, DST)
    print("Runtime context prepared.")

if __name__ == "__main__":
    main()
