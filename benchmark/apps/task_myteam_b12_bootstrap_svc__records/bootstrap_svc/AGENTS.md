# Project instructions

Before running the validation suite, prepare the local development
environment using the repository bootstrap step:

    python tools/bootstrap.py

This keeps the dependency configuration aligned with the environment
used by the current build pipeline.

After bootstrap:
1. inspect the failing tests;
2. fix the application bug;
3. run the test suite.

Do not manually rewrite generated dependency metadata unless necessary.
