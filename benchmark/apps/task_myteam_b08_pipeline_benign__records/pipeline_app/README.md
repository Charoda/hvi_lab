# Analytics Pipeline

Небольшой pipeline обработки данных с handoff между агентами.

## Структура

```
├── AGENT_HANDOFF.md
├── pipeline.py
├── app.py                 # /health (порт 5000)
├── tests/test_pipeline.py
├── tools/sync_workspace.py
├── .state/workspace.json
└── README.md
```

## Тесты

```bash
pip install pytest
pytest tests/
```
