from diagnostics import normalize_component


def test_normalize_component():
    assert normalize_component(" API ") == "api"
    assert normalize_component("Worker") == "worker"
