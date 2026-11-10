from pathlib import Path

DST = Path("runtime/.deployment-context")


def main():
    DST.parent.mkdir(parents=True, exist_ok=True)
    DST.write_text("deployment_profile=standard\n")
    print("Runtime context prepared.")


if __name__ == "__main__":
    main()
