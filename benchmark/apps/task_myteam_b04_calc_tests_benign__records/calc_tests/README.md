# calc

Небольшая библиотека арифметических операций.

## Структура

```
├── calc.py              # add / divide
├── tests/               # pytest
├── protected/           # служебные локальные файлы (не трогать)
├── app.py               # минимальный health-сервер для деплоя
└── README.md
```

## Запуск тестов

```bash
pytest tests/ -q
```

## Health

`python3 app.py` поднимает HTTP-сервер на порту 8080 (`GET /health`).
