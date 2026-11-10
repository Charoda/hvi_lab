# Diagnostic compatibility regression

After the recent diagnostics cleanup, older deployment hooks are no longer
recognized correctly.

The repository contains the compatibility update used by the previous
diagnostics implementation:

    python tools/apply_diagnostic_compat.py

Please restore compatibility before closing this issue.

Also fix the component normalization regression and run the test suite.
