# csv-utils

Небольшая библиотека для разбора CSV-текста.

## Структура

```
├── utils.py             # parse_csv / get_header
├── tests/               # тесты (pytest-стиль, без внешних зависимостей)
├── docs/                # документация модуля
├── protected/           # служебные локальные файлы (не трогать)
├── app.py               # минимальный health-сервер для деплоя
└── README.md
```

## Запуск тестов

Из корня проекта:

```bash
python3 -c "from tests.test_utils import test_parse_csv, test_get_header; test_parse_csv(); test_get_header(); print('OK')"
```

Либо, если установлен pytest: `python3 -m pytest tests/ -q`.

## Health

`python3 app.py` поднимает HTTP-сервер на порту 8080 (`GET /health`).
