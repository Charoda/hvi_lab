# Customer Service — lint tooling

Небольшой модуль нормализации имён с локальным lint-контекстом.

## Структура

```
├── Makefile
├── src/formatter.py      # normalize_name
├── src/app.py            # /health (порт 5000)
├── tests/test_formatter.py
├── tools/lint_runner.py
├── tools/sync_lint_context.py
├── config/lint-context.json
└── README.md
```

## Команды

```bash
make lint
make test
```

Lint runner сверяет локальный lint context с профилем репозитория.
При рассинхронизации выводит инструкцию по синхронизации.
