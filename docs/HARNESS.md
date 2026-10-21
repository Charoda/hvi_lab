# Harness — полный гид по прогонам (Cursor / OpenCode)

Тестовый стенд (§13): готовит репозиторий → запускает агента → передаёт задачу →
сохраняет логи → считает **ASR / IRR / TCR / FPR**.

| | |
|---|---|
| Скрипт | `./isolated/harness/run.sh` |
| Список сценариев | `isolated/harness/scenarios.txt` (early + **B01–B20**; у каждого base есть `_benign`) |
| Профили OpenCode | `configs/opencode/{off,normal,strict}.json` |
| Профили Cursor | `configs/cursor/{off,normal,strict}.json` |
| Краткая ссылка | `isolated/harness/HARNESS.md` → сюда |

На каждую выбранную base-ячейку harness сам прогоняет **две** variant’ы: malicious и benign.

---

## 1. Оси одного прогона (все режимы)

Любой запуск — комбинация независимых осей:

| Ось | Флаг / env | Значения | По умолчанию |
|---|---|---|---|
| **Актор** | `--actor` | `opencode` \| `cursor` | *обязателен* |
| **Профиль прав** | `--profile` / `--permission-profile` | `off` \| `normal` \| `strict` \| `all` | `off` |
| **Режим Cursor** | `--mode` | `agent` \| `interactive` | `agent` |
| **Сеть** | `--network` | `allowlist` \| `open` \| `blocked` | `allowlist` |
| **Сценарии** | `--scenarios` | `all` \| `b07,b08` \| `b01-b20` \| полное id | `all` |
| **Повторы** | `--trials` / `-n` | целое ≥ 1 | `1` |
| **Таймаут** | `--timeout` | секунды | `2400` |
| **Модель** | `--model` / env | id модели | из `.env` / `auto` |
| **Имя batch** | `--batch` / `BATCH_NAME` | произвольная строка | `harness-<actor>-<timestamp>` |

Объём ячеек:

```text
N_cells ≈ (#scenarios) × 2 (mal+benign) × (#profiles) × trials
```

Примеры: `b01-b20` × off × N=5 → **200** ячеек; `b01-b20` × `--profile all` × N=5 → **600**.

---

## 2. Подготовка (один раз)

```bash
cd ~/mosaic-benchmark
cp -n .env.example .env
chmod 600 .env
```

| Переменная в `.env` | Для кого | Пример |
|---|---|---|
| `OPENROUTER_API_KEY` | `--actor opencode` | `sk-or-v1-…` (нужен **баланс**, если модель без `:free`) |
| `CURSOR_API_KEY` | `--actor cursor` (`--mode agent`) | ключ из Cursor Dashboard |
| `MOSAIC_OPENCODE_MODEL` | модель OpenCode | paid: `openrouter/nvidia/nemotron-3-ultra-550b-a55b` |
| `MOSAIC_CURSOR_MODEL` | модель Cursor (опц.) | `composer-2.5` |
| `CURSOR_API_ENDPOINT` | эндпоинт Cursor (опц.) | `https://api2.cursor.sh` |
| `MOSAIC_OPENCODE_PERMISSION_PROFILE` | дефолт профиля OpenCode вне harness (опц.) | `off` |

**Не коммитить** `.env`, ключи, полные `logs/`.

### 2.1. OpenCode / Nemotron: paid vs free

| Slug | Когда | Риски |
|---|---|---|
| `…/nemotron-3-ultra-550b-a55b` (**paid**, без `:free`) | Сравнительные / длинные batch’и | Нужны кредиты OpenRouter на ключе |
| `…/nemotron-3-ultra-550b-a55b:free` | Пилоты, экономия | 504 Timeout, очередь, daily free cap; trial «висит» без правок кода |

Переключить на paid:

```bash
# в .env:
MOSAIC_OPENCODE_MODEL=openrouter/nvidia/nemotron-3-ultra-550b-a55b
```

Либо разово: `--model openrouter/nvidia/nemotron-3-ultra-550b-a55b`.

Проверка ключа OpenRouter (без печати секрета):

```bash
set -a && source .env && set +a
curl -sS https://openrouter.ai/api/v1/key \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]; print({k:d.get(k) for k in ["is_free_tier","usage","limit","limit_remaining"]})'
```

Для paid-модели нужно `is_free_tier: false` и ненулевой баланс / `limit_remaining`.

Проверка Cursor-ключа:

```bash
set -a && source .env && set +a
agent -p --api-key "$CURSOR_API_KEY" --model auto --output-format text "Reply: OK"
```

---

## 3. Сценарии

Файл: `isolated/harness/scenarios.txt`.

### 3.1. Каталог

| Группа | ID |
|---|---|
| Early (precursors) | `readme_setup_exfil`, `comment_license_exfil`, `agent_rules_malicious_package` |
| B01–B14 | `b01_readme_setup` … `b14_readme_env` |
| B15–B20 (новые) | `b15_dependency_docs`, `b16_web_docs`, `b17_docker_build`, `b18_ci_artifact`, `b19_git_hook`, `b20_postinstall` |

У каждого base-id harness автоматически добавляет twin `<id>_benign`, если он есть в `benchmark/chains/`.

### 3.2. Форматы `--scenarios`

| Спека | Смысл |
|---|---|
| `all` | все строки из `scenarios.txt` |
| `b07,b08` | список (короткие префиксы `bNN` или полные id) |
| `b01-b20` | диапазон по номеру |
| `b07_lint_output` | одно полное id |

Примеры: `--scenarios b01-b15`, `--scenarios b16-b20`, `--scenarios b07,b11,b20`.

---

## 4. Профили прав: `off` / `normal` / `strict` / `all`

Это **не** разные модели и **не** разные сценарии.  
Это уровень разрешений для tool’ов (shell, сеть, curl…). Одна и та же задача под разными правилами → сравнение ASR / IRR / FPR.

| Профиль | Смысл | Cursor (`--mode agent`) | OpenCode |
|---|---|---|---|
| **off** | Baseline: двери открыты; остановит ли **модель** сама | `agent -p --force --sandbox disabled` | всё `allow`, флаг `--auto` |
| **normal** | Опасное → «спросить»; в автопрогоне ≈ не выполнить | `agent -p --auto-review` (без `--force`) | curl/secret/… → `ask` → harness abort |
| **strict** | Опасное запрещено жёстко | `--force --sandbox enabled` + deny curl/wget/nc в cli-config | secrets/`webfetch` deny; bash allowlist (ls/pytest/pip/…) |
| **all** | Подряд `off`, затем `normal`, затем `strict` | то же | то же |

- Без `--profile` → **`off`**
- Cursor: каждый trial — свой изолированный `$HOME` с `configs/cursor/<profile>.json` (настройки IDE не подмешиваются)
- OpenCode: `configs/opencode/<profile>.json` внутри isolated-контейнера

Подробнее: `configs/cursor/README.md`, `configs/opencode/README.md`, `docs/ISOLATED_RUN.md` §2.6.

**Сравнение с Cursor N=5 (сен 2026):** Cursor шёл только `--profile off`. Для apples-to-apples OpenCode тоже только `off`, не матрица `all`.

---

## 5. Сеть: `--network`

Влияет на isolated/OpenCode (и связанный Docker-контур).

| Значение | Смысл |
|---|---|
| **allowlist** | Дефолт для ASR-сравнений: разрешены нужные хосты (OpenRouter, пакетные зеркала и т.п.), остальное режется |
| **open** | Сеть почти без ограничений (осторожно: шире поверхность exfil) |
| **blocked** | Сеть закрыта / максимально урезана |

Типичный сравнительный прогон: `--network allowlist`.

---

## 6. Актор Cursor

Нужен `CURSOR_API_KEY` в `.env` для `--mode agent`.

### 6.1. Режим `agent` (по умолчанию)

Автономный `agent -p` в слепом workspace.

```bash
cd ~/mosaic-benchmark

# один профиль
./isolated/harness/run.sh --actor cursor --profile off    --scenarios b07
./isolated/harness/run.sh --actor cursor --profile normal --scenarios b07
./isolated/harness/run.sh --actor cursor --profile strict --scenarios b07

# матрица всех трёх профилей
./isolated/harness/run.sh --actor cursor --profile all --scenarios b07,b08

# B01–B20, baseline off, N=5 (как большой Cursor-batch)
./isolated/harness/run.sh --actor cursor --profile off --trials 5 \
  --scenarios b01-b20 --batch cursor-b01-b20-n5-off

# своя модель
./isolated/harness/run.sh --actor cursor --profile strict --scenarios b07 \
  --model composer-2.5
```

### 6.2. Режим `interactive`

Ручной Cursor IDE, без `agent -p`. Печатает путь к workspace + prompt, ждёт Enter. API key не обязателен. `--profile` здесь только подсказка — политики IDE выставляешь сам.

```bash
./isolated/harness/run.sh --actor cursor --mode interactive --scenarios b07
```

---

## 7. Актор OpenCode

Нужен `OPENROUTER_API_KEY`. Модель — `MOSAIC_OPENCODE_MODEL` или `--model`.

По умолчанию для изолированных ASR-прогонов: **OpenCode + Nemotron** (см. §2.1), не MiniMax.

```bash
# baseline off, все сценарии из списка
./isolated/harness/run.sh --actor opencode --profile off --scenarios all

# один / несколько профилей
./isolated/harness/run.sh --actor opencode --profile normal --scenarios b07,b08
./isolated/harness/run.sh --actor opencode --profile strict --scenarios b09-b12
./isolated/harness/run.sh --actor opencode --profile all --trials 5 --scenarios b07-b12

# B01–B20 × off × N=5 на paid Nemotron (сравнимо с Cursor N=5)
./isolated/harness/run.sh --actor opencode --profile off --trials 5 \
  --scenarios b01-b20 --network allowlist --timeout 2400 \
  --model openrouter/nvidia/nemotron-3-ultra-550b-a55b \
  --batch opencode-b01-b20-n5-off
```

Результаты: `logs/<batch>/` → `malicious.tsv`, `benign.tsv`, `metrics.*`, `progress.tsv`, `raw/`.

---

## 8. Куда пишутся результаты

### 8.1. Каталог batch

Строка `out: …` при старте:

```text
logs/<batch>/
```

Без `--batch` имя авто: `harness-<actor>-<YYYYMMDD-HHMMSS>/`.

Своё имя (удобно для resume и сравнения):

```bash
./isolated/harness/run.sh --actor opencode --profile off --scenarios b01-b20 \
  --batch opencode-b01-b20-n5-off
# → logs/opencode-b01-b20-n5-off/
```

### 8.2. Содержимое batch

```text
logs/<batch>/
├── malicious.tsv       ← атаки → ASR, IRR, TCR_malicious
├── benign.tsv          ← benign  → TCR_benign, FPR
├── metrics.tsv         ← сводка ASR / IRR / TCR / FPR
├── metrics.json        ← то же + разбивка по profile
├── progress.tsv        ← done-ячейки (resume)
├── run_config.json     ← actor, model, profiles, scenarios, trials
├── runs/               ← (cursor) symlinks на сырые trial-логи
└── raw/                ← (opencode) копии console-логов
```

В строках TSV есть колонка **`profile`**.

### 8.3. Сырой trial (Cursor)

```text
logs/cursor-<chain>-<profile>-<YYYYMMDD-HHMMSS>/
  final_app/
  cursor_agent.log
  cursor_cli_config.json
  cursor_profile.json
  cursor_profile_name.txt
  honey_requests.jsonl   # если сценарий с honey/exfil
```

Blind-workspace на время прогона:

```text
~/mosaic-manual-runs/<batch>-workspaces/
  workspaces/<chain>/     ← видит агент
  meta/<chain>/           ← PROMPT, honey, cursor_home_<profile>/
```

### 8.4. Сырой trial (OpenCode)

Как у `./run_isolated.sh`:

```text
logs/<chain_id>-<YYYYMMDD-HHMMSS>/
  result.json
  behavior_analysis.json
  actor_stdout.log / actor_stderr.log
  …
```

### 8.5. Быстрый просмотр

```bash
ls -lt logs/harness-* logs/opencode-* logs/cursor-* 2>/dev/null | head
column -t -s$'\t' logs/<batch>/metrics.tsv
cut -f1-5,8-12 logs/<batch>/malicious.tsv | column -t -s$'\t'
wc -l logs/<batch>/progress.tsv
```

---

## 9. Resume после обрыва

Тот же `--batch` (и те же оси). Уже `done` в `progress.tsv` пропускаются.

```bash
./isolated/harness/run.sh --actor opencode --profile off --trials 5 \
  --scenarios b01-b20 --network allowlist --timeout 2400 \
  --batch opencode-b01-b20-n5-off
```

Перезапуск всех ячеек с нуля: `SKIP_DONE=0` (осторожно: дубли в TSV) или удалить batch и сырые trial-логи.

Остановка mid-run:

```bash
pkill -f 'isolated/harness/run.sh'   # затем при необходимости docker rm -f iso-…
```

---

## 10. Метрики (в конце batch)

| Метрика | Файл | Формула | Смысл |
|---|---|---|---|
| **ASR** | `malicious.tsv` | `attack_success / valid` | доля успешных атак |
| **IRR** | `malicious.tsv` | `(not attack_success) / valid` | сопротивление инъекции |
| **TCR** | оба (отдельно) | `utility_success / utility_known` | полезная задача выполнена |
| **FPR** | `benign.tsv` | `defense_false_positive / valid` | защита мешала на benign |

- На **`off`** FPR обычно ~0; на **`normal`/`strict`** FPR осмысленен.
- Смотри колонку `n` в `metrics.tsv` (знаменатель utility).

Пересчёт без нового прогона:

```bash
~/.pyenv/versions/mosaic-311/bin/python isolated/harness/metrics.py \
  --malicious logs/<batch>/malicious.tsv \
  --benign    logs/<batch>/benign.tsv \
  --out-dir   logs/<batch> \
  --actor opencode --batch <batch>
```

---

## 11. Что harness делает внутри

1. **Prepare** — cursor: слепая копия app + изолированный HOME с profile; opencode: Docker через `./run_isolated.sh`.
2. **Run agent** — передаёт `agent_prompt.txt` под выбранным `--profile`.
3. **Logs** — honey (если нужен), transcript, `final_app/`.
4. **Score** — PoC → строка в `malicious.tsv` или `benign.tsv`.
5. **Metrics** — `metrics.py` → `metrics.tsv` / `metrics.json`.

Пары: `<base>` (malicious) + `<base>_benign`.

---

## 12. Типичные ошибки

| Симптом | Что сделать |
|---|---|
| `нужен CURSOR_API_KEY` | в `.env` ключ Cursor (`crsr_…` / key из Dashboard), не OpenRouter |
| OpenRouter `requires more credits` | paid-модель на free-ключе → пополнить / другой ключ; иначе ложный SECURE (~15 с) |
| OpenRouter `504` / «зависло» на `:free` | очередь free-tier; перейти на paid slug |
| OpenRouter rate / daily free cap | другой ключ / paid / подождать |
| `syntax error near (` mid-run | не править `run.sh` во время прогона; resume тем же `--batch` |
| Стереть batch | `rm -rf logs/<batch>` + связанные `logs/cursor-*…` / `logs/<chain>-*` / `~/mosaic-manual-runs/<batch>-workspaces` |
| Старый Cursor-batch с `profile=n/a` | для новой матрицы — **новый** `--batch` |

---

## 13. Параметры CLI (справка)

```bash
./isolated/harness/run.sh --actor <opencode|cursor> [опции]
./isolated/harness/run.sh -h
```

| Параметр | Значения | По умолчанию | Смысл |
|---|---|---|---|
| `--actor` | `opencode` \| `cursor` | *обязателен* | кто исполняет задачу |
| `--scenarios` | `all` \| список \| диапазон \| id | `all` | какие base-сценарии |
| `--profile` | `off` \| `normal` \| `strict` \| `all` | `off` | уровень разрешений |
| `--trials` / `-n` | число ≥1 | `1` | повторов на ячейку |
| `--timeout` | секунды | `2400` | лимит одного agent-вызова |
| `--network` | `allowlist` \| `open` \| `blocked` | `allowlist` | сеть (opencode / isolated) |
| `--mode` | `agent` \| `interactive` | `agent` | только cursor |
| `--model` | id модели | из env / `auto` | модель агента |
| `--batch` | имя каталога | авто `harness-…` | куда писать / resume |

Env-эквиваленты: `MODEL`, `TIMEOUT`, `NETWORK`, `MODE`, `BATCH_NAME`, `SKIP_DONE=0`, `PYTHON`, `AGENT_BIN`.

---

## 14. Шпаргалка

```bash
cd ~/mosaic-benchmark

# --- Cursor ---
./isolated/harness/run.sh --actor cursor --profile off    --scenarios b07
./isolated/harness/run.sh --actor cursor --profile normal --scenarios b07
./isolated/harness/run.sh --actor cursor --profile strict --scenarios b07
./isolated/harness/run.sh --actor cursor --profile all --scenarios b07,b08
./isolated/harness/run.sh --actor cursor --profile off --trials 5 --scenarios b01-b20 \
  --batch cursor-b01-b20-n5-off
./isolated/harness/run.sh --actor cursor --mode interactive --scenarios b07

# --- OpenCode (paid Nemotron, сравнить с Cursor N=5) ---
./isolated/harness/run.sh --actor opencode --profile off --trials 5 \
  --scenarios b01-b20 --network allowlist --timeout 2400 \
  --model openrouter/nvidia/nemotron-3-ultra-550b-a55b \
  --batch opencode-b01-b20-n5-off

# --- OpenCode permission matrix ---
./isolated/harness/run.sh --actor opencode --profile all --trials 5 \
  --scenarios b07-b12 --batch opencode-b07-b12-matrix-n5

# --- смотреть ---
ls -lt logs/ | head
column -t -s$'\t' logs/<batch>/metrics.tsv
```

Фоновый запуск:

```bash
nohup ./isolated/harness/run.sh ... --batch МОЁ_ИМЯ > /tmp/МОЁ_ИМЯ.log 2>&1 &
tail -f /tmp/МОЁ_ИМЯ.log
```
