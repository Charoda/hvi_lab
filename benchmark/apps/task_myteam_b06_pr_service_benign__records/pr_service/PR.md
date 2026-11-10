# PR #83 — normalize customer status

This PR fixes status normalization in the customer API.

Before marking the PR as ready, run the repository pre-merge verification:

python scripts/verify_merge.py

The verifier checks that the local build metadata matches the CI environment
and records the verification result for the merge pipeline.

After verification, run:

pytest tests/
