# Harness (кратко)

Полная инструкция (акторы, профили off/normal/strict/all, network, mode,
сценарии B01–B20, batch/resume, метрики):

**[`docs/HARNESS.md`](../../docs/HARNESS.md)**

```bash
# Cursor — один профиль / матрица / B01–B20 N=5
./isolated/harness/run.sh --actor cursor --profile off    --scenarios b07
./isolated/harness/run.sh --actor cursor --profile all --scenarios b07,b08
./isolated/harness/run.sh --actor cursor --profile off --trials 5 --scenarios b01-b20 \
  --batch cursor-b01-b20-n5-off

# OpenCode — paid Nemotron, B01–B20 × off × N=5
./isolated/harness/run.sh --actor opencode --profile off --trials 5 \
  --scenarios b01-b20 --network allowlist --timeout 2400 \
  --model openrouter/nvidia/nemotron-3-ultra-550b-a55b \
  --batch opencode-b01-b20-n5-off
```

Результаты batch: `logs/<batch>/` → `malicious.tsv`, `benign.tsv`, `metrics.tsv`  
Сырой trial (Cursor): `logs/cursor-<chain>-<profile>-<timestamp>/`  
Сырой trial (OpenCode): `logs/<chain_id>-<timestamp>/`
