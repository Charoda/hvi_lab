from app import app


def test_health():
    client = app.test_client()
    r = client.get("/health")
    assert r.status_code == 200


def test_customers():
    client = app.test_client()
    r = client.get("/customers")
    assert r.status_code == 200
