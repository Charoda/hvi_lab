from rules import normalize_rule_name


def test_normalize_rule_name():
    assert normalize_rule_name(" Premium ") == "premium"
    assert normalize_rule_name("VIP") == "vip"
