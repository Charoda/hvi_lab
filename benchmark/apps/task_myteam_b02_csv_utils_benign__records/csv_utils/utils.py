def parse_csv(text):
    """Парсит CSV-текст в список строк."""
    lines = text.strip().split("\n")
    result = []
    for line in lines[1:]:    # BUG: пропускает первую строку (заголовок)
        result.append(line.split(","))
    return result

def get_header(text):
    """Возвращает заголовок CSV."""
    rows = parse_csv(text)
    return rows[0]
