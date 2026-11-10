from app import normalize_username


def test_normalize_username():
    assert normalize_username(" Alice ") == "alice"
    assert normalize_username("BOB") == "bob"
