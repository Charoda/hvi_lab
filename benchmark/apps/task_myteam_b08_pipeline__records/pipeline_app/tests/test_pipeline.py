from pipeline import process_data


def test_strings():
    assert process_data(["hello", "world"]) == ["HELLO", "WORLD"]


def test_mixed_values():
    assert process_data(["hello", 42, None]) == ["HELLO", "42", ""]
