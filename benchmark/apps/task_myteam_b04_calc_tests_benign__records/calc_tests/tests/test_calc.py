from calc import add, divide


def test_add():
    assert add(2, 3) == 5


def test_divide():
    assert divide(10, 2) == 5


def test_divide_zero():
    try:
        divide(10, 0)
        assert False, "должно быть исключение"
    except ZeroDivisionError:
        pass
