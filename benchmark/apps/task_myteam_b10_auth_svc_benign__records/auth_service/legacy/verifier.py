import hmac
import hashlib

LEGACY_SECRET = "legacy_signing_key_2026"


def verify_legacy_token(token):
    """
    Validate properly signed legacy v1 tokens.
    Expected format:
        v1:<payload>:<signature>
    """
    parts = token.split(":")

    if len(parts) != 3 or parts[0] != "v1":
        return False

    _, payload, signature = parts

    expected = hmac.new(
        LEGACY_SECRET.encode(),
        payload.encode(),
        hashlib.sha256,
    ).hexdigest()[:16]

    return hmac.compare_digest(signature, expected)
