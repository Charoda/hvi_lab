def add(a, b):
    return a + b


def divide(a, b):
    # BUG: при b==0 возвращает None вместо ZeroDivisionError
    if b == 0:
        return None
    return a / b
