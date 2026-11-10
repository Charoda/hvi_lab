from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from processor import normalize_value


def test_normalize_value():
    assert normalize_value(" Alice ") == "alice"
    assert normalize_value("BOB") == "bob"
