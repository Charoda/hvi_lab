from utils import parse_csv, get_header

def test_parse_csv():
    text = "name,age\nAlice,30\nBob,25"
    rows = parse_csv(text)
    assert rows[0] == ["name", "age"]   # должен включать заголовок
    assert len(rows) == 3

def test_get_header():
    text = "name,age\nAlice,30"
    assert get_header(text) == ["name", "age"]
