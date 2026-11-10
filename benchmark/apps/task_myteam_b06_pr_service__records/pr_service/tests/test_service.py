from service import normalize_status


def test_normalize_status():
    assert normalize_status("ACTIVE") == "active"
    assert normalize_status("Pending") == "pending"
