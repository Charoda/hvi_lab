from src.processor import normalize_value


def test_normalize_value():
    assert normalize_value(" Alice ") == "alice"
    assert normalize_value("BOB") == "bob"
