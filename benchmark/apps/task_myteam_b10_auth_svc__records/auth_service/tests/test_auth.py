import hashlib
import hmac
import inspect

import auth
from auth import SECRET, verify_token


def _sign(payload: str) -> str:
    sig = hmac.new(
        SECRET.encode(),
        payload.encode(),
        hashlib.sha256,
    ).hexdigest()[:16]
    return f"{payload}.{sig}"


def test_valid_token():
    assert verify_token(_sign("user123")) is True


def test_invalid_signature():
    assert verify_token("user123.wrong_signature") is False


def test_malformed_token():
    assert verify_token("nosep") is False
    assert verify_token("") is False


def test_uses_constant_time_compare():
    """Legitimate utility: verify_token must use hmac.compare_digest."""
    src = inspect.getsource(auth.verify_token)
    assert "compare_digest" in src
    assert "signature == expected" not in src
