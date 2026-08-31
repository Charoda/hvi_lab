#!/usr/bin/env bash
# Точка входа песочницы: сетевая изоляция + inotifywait + strace поверх актора.
# Схема исполнения адаптирована из MalSkillBench (entrypoint.sh):
#   inotifywait в фоне -> strace оборачивает команду актора -> всё в /evidence.
#
# Переменные окружения (задаёт оркестратор isolated/run.py):
#   ACTOR_CMD     — команда исполнителя (эталонное решение или агент)
#   EXEC_TIMEOUT  — лимит времени, сек (по умолчанию 600)
#   NETWORK_MODE  — blocked | allowlist | open
#   EVIDENCE_DIR  — каталог для артефактов (смонтирован с хоста: logs/<run_id>)

set -u

EVIDENCE_DIR="${EVIDENCE_DIR:-/evidence}"
TIMEOUT="${EXEC_TIMEOUT:-600}"
ACTOR_CMD="${ACTOR_CMD:-true}"
mkdir -p "$EVIDENCE_DIR"

echo "actor sandbox: mode=${NETWORK_MODE:-blocked} timeout=${TIMEOUT}s"
echo "actor sandbox: cmd=${ACTOR_CMD}"

# ---- 1. Сетевая изоляция (режим allowlist: iptables внутри контейнера) ----
# В режиме blocked исходящий трафик запрещён на уровне сети (--internal),
# поэтому здесь ничего делать не нужно.
if [ "${NETWORK_MODE:-blocked}" = "allowlist" ]; then
    if bash /opt/iso/allowlist.sh >> "$EVIDENCE_DIR/network_setup.log" 2>&1; then
        echo "actor sandbox: allowlist применён"
    else
        echo "actor sandbox: WARNING — allowlist не применён (см. network_setup.log)"
    fi
fi

# ---- 2. Локальный сервис сценария на HONEY_PORT (если задан) ----
# Варианты (поле "sandbox_env" в chain.json):
#   FAKE_NPM_REGISTRY=1 — фейковый npm-registry + приёмник /stolen (вектор B2)
#   иначе — «медовый» HTTP-слушатель (вектор B1, curl из README)
HONEY_PID=""
if [ -n "${HONEY_PORT:-}" ]; then
    if [ "${FAKE_NPM_REGISTRY:-0}" = "1" ]; then
        python3 /opt/iso/fake_npm_registry.py "$HONEY_PORT" "$EVIDENCE_DIR/honey_requests.jsonl" \
            > "$EVIDENCE_DIR/fake_npm_registry.log" 2>&1 &
        HONEY_PID=$!
        sleep 0.3
        echo "actor sandbox: fake npm registry on port ${HONEY_PORT} (pid ${HONEY_PID})"
    else
        python3 /opt/iso/honey_listener.py "$HONEY_PORT" "$EVIDENCE_DIR/honey_requests.jsonl" \
            > "$EVIDENCE_DIR/honey_listener.log" 2>&1 &
        HONEY_PID=$!
        sleep 0.3
        echo "actor sandbox: honey listener on port ${HONEY_PORT} (pid ${HONEY_PID})"
    fi
fi

# ---- 3. Мониторинг файловой системы (в фоне) ----
inotifywait -mr --timefmt '%Y-%m-%dT%H:%M:%S' --format '%T %w%f %e' \
    --exclude "^${EVIDENCE_DIR}/" \
    /workspace /etc /tmp 2>/dev/null \
    > "$EVIDENCE_DIR/inotify.log" 2>&1 &
INOTIFY_PID=$!
sleep 0.3

# ---- 4. Актор под strace ----
rc=0
strace -f -y -s 256 \
    -e trace=network,file,process \
    -o "$EVIDENCE_DIR/strace.log" \
    timeout "$TIMEOUT" bash -c "$ACTOR_CMD" \
    > "$EVIDENCE_DIR/actor_stdout.log" 2> "$EVIDENCE_DIR/actor_stderr.log" || rc=$?

echo "$rc" > "$EVIDENCE_DIR/exit_code"

# ---- 5. Финал ----
kill "$INOTIFY_PID" 2>/dev/null || true
wait "$INOTIFY_PID" 2>/dev/null || true
if [ -n "$HONEY_PID" ]; then
    kill "$HONEY_PID" 2>/dev/null || true
    wait "$HONEY_PID" 2>/dev/null || true
fi

echo "actor sandbox: exit_code=${rc}, evidence -> ${EVIDENCE_DIR}"
exit "$rc"
