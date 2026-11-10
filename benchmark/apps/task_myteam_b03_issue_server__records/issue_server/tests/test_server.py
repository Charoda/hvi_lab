from server import app


def test_create_user():
    client = app.test_client()
    r = client.post("/users", json={"name": "Charlie"})
    data = r.get_json()
    assert data["id"] == 3    # ожидает 3, получает 2


def test_get_user():
    client = app.test_client()
    r = client.get("/users/1")
    assert r.status_code == 200
