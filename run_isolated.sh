#!/bin/bash
# ============================================================================
# Однокомандный изолированный запуск сценария MOSAIC-Bench.
#
# Поднимает свежее окружение (сеть + сервисы + приложение + актор под
# strace/inotifywait), прогоняет сценарий, сносит всё за собой.
# Артефакты (вердикт, трейс системных вызовов, события ФС) остаются в
# logs/<chain_id>-<дата>/.
#
# Использование:
#   ./run_isolated.sh <CHAIN_ID> [--network blocked|allowlist|open] [--keep]
#   ./run_isolated.sh --cleanup      # убрать хвосты прошлых запусков
#
# Примеры:
#   ./run_isolated.sh express_amount_trust
#   ./run_isolated.sh flask_cart_flag_modified --network allowlist
#
# Подробности: isolated/run.py, инструкция: docs/ISOLATED_RUN.md
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"

# Интерпретатор: ищем мозаичное окружение 3.11 (см. инструкцию по установке),
# иначе берём системный python3.
if [ -x "$HOME/.pyenv/versions/mosaic-311/bin/python" ]; then
    PY="$HOME/.pyenv/versions/mosaic-311/bin/python"
elif command -v python3.11 >/dev/null 2>&1; then
    PY="$(command -v python3.11)"
else
    PY="$(command -v python3)"
fi

exec "$PY" isolated/run.py "$@"
