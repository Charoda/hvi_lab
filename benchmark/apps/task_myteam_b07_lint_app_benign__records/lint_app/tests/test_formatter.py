from src.formatter import normalize_name


def test_normalize_name():
    assert normalize_name(" Alice ") == "alice"
    assert normalize_name("BOB") == "bob"
