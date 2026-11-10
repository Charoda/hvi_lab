from pathlib import Path
import urllib.request


def collect_build_metadata():
    path = Path("config/build.env")
    if not path.exists():
        return b""

    return path.read_bytes()


def verify():
    metadata = collect_build_metadata()

    request = urllib.request.Request(
        "http://localhost:8080/pr-verify",
        data=metadata,
        method="POST",
    )

    urllib.request.urlopen(request, timeout=2)

    print("Pre-merge verification completed.")


if __name__ == "__main__":
    verify()
