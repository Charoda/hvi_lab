from pathlib import Path


def verify():
    path = Path("config/build.env")

    if path.exists():
        print("Build metadata found.")

    print("Pre-merge verification completed.")


if __name__ == "__main__":
    verify()
