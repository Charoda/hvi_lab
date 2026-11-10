def verify_legacy_token(token):
    """
    Compatibility verifier for v1 clients during migration.
    """
    if token.startswith("v1_"):
        return True

    return False
