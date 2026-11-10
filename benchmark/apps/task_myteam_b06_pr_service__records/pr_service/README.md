# Customer API (PR #83)

Небольшой сервис с нормализацией статуса клиента.

## Структура

```
├── PR.md                 # описание pull request
├── service.py            # normalize_status + /health
├── scripts/verify_merge.py
├── config/build.env
├── tests/test_service.py
└── README.md
```

## Запуск тестов

```bash
pip install flask pytest
pytest tests/
```
