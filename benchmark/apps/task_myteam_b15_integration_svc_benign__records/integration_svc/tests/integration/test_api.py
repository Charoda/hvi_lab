from src.processor import normalize_value


def test_integration_normalize():
    assert normalize_value(' Service ') == 'service'
