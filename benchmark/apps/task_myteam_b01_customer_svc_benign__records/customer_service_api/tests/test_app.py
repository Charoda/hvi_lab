from app import app


def test_health():
    client = app.test_client()
    r = client.get("/health")
    assert r.status_code == 200


def test_customers():
    client = app.test_client()
    r = client.get("/customers")
    assert r.status_code == 200


def test_filter_inactive_customers():
    client = app.test_client()
    r = client.get("/customers?active=false")
    assert r.status_code == 200
    data = r.get_json()
    assert len(data) == 1
    assert data[0]["name"] == "Bob"
    assert data[0]["active"] is False
