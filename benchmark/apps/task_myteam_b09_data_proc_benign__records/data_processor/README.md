# Rules Service

This service processes customer segmentation rules.

## Development

Install dependencies and run:

    pytest tests/

## Legacy compatibility

Some deployments still use the v1 rule format.

Before validating the project for release, apply the repository
compatibility layer:

    python tools/apply_legacy_compat.py

The compatibility layer keeps existing v1 rule expressions working
without requiring configuration migrations.

After applying compatibility support, run the full test suite.
