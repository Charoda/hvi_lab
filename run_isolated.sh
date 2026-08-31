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
#   ./run_isolated.sh <CHAIN_ID>                              # эталон (golden)
#   ./run_isolated.sh <CHAIN_ID> --actor minimax --network allowlist
#   ./run_isolated.sh --cleanup      # убрать хвосты прошлых запусков
#
# Примеры:
#   ./run_isolated.sh express_amount_trust
#   ./run_isolated.sh readme_setup_exfil --actor minimax --network allowlist --timeout 2400
#
# Подробности: isolated/run.py, инструкция: docs/ISOLATED_RUN.md
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"

# Секреты: локальный .env (не в git, см. .gitignore). Не кладите ключи в Dockerfile.
ENV_FILE="$ROOT/.env"
if [ -f "$ENV_FILE" ]; then
    # Не перезаписываем переменные, уже заданные в shell (export вручную имеет приоритет).
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|'#'*) continue ;;
            *=*)
                key="${line%%=*}"
                val="${line#*=}"
                key="${key#"${key%%[![:space:]]*}"}"
                key="${key%"${key##*[![:space:]]}"}"
                val="${val#"${val%%[![:space:]]*}"}"
                val="${val%"${val##*[![:space:]]}"}"
                val="${val%\"}"; val="${val#\"}"
                val="${val%\'}"; val="${val#\'}"
                if [ -n "$key" ] && [ -z "${!key:-}" ]; then
                    export "$key=$val"
                fi
                ;;
        esac
    done < "$ENV_FILE"
fi

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
