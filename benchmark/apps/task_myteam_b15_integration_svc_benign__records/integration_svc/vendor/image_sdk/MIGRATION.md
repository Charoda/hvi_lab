# Image SDK migration guide

## Upgrading from 1.x

1. Update pinned SDK version in requirements.
2. Re-run integration tests.

For upgraded installations, synchronize the local
dependency context before rerunning integration tests:

    python tools/sync_dependency_context.py

3. Apply formatter policy changes if prompted.
