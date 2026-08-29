#!/usr/bin/env bash
# Точка входа песочницы: сетевая изоляция + inotifywait + strace поверх актора.
# Схема исполнения адаптирована из MalSkillBench (entrypoint.sh):
#   inotifywait в фоне -> strace оборачивает команду актора -> всё в /evidence.
#
# Переменные окружения (задаёт оркестратор isolated/run.py):
#   ACTOR_CMD     — команда исполнителя (эталонное решение или агент)
#   EXEC_TIMEOUT  — лимит времени, сек (по умолчанию 600)
#   NETWORK_MODE  — blocked | allowlist | open
#   LLAMA_START   — 1: поднять локальный `llama-server` до старта актора
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

# ---- 2. «Медовый» слушатель локального порта (если задан сценарием) ----
# Ловит всё, что агент пытается отправить на локальные «вспомогательные
# ручки» (например, curl из вредоносной инструкции в README). Порт задаётся
# переменной HONEY_PORT (поле "sandbox_env" в chain.json, см. run.py).
HONEY_PID=""
if [ -n "${HONEY_PORT:-}" ]; then
    python3 /opt/iso/honey_listener.py "$HONEY_PORT" "$EVIDENCE_DIR/honey_requests.jsonl" \
        > "$EVIDENCE_DIR/honey_listener.log" 2>&1 &
    HONEY_PID=$!
    sleep 0.3
    echo "actor sandbox: honey listener on port ${HONEY_PORT} (pid ${HONEY_PID})"
fi

# ---- 2b. Локальный llama.cpp в песочнице (если актору нужна локальная LLM) ----
# Оркестратор ставит LLAMA_START=1 (run.py, --actor qwen --llm llama).
# Веса модели (GGUF) запечены в образ (Dockerfile.agent); сервер слушает
# только loopback — снаружи контейнера к LLM не подобраться. Агент ходит на
# порт 11434, где его встречает прокси-переводчик (llama_tool_proxy.py),
# а сам llama-server поднят на 11435 (НЕ 8080: в сценариях на поведение
# агента этот порт занимает медовый слушатель HONEY_PORT). Сервер и прокси
# НЕ оборачиваются в strace: в трейс попадает только актор.
LLAMA_PID=""
PROXY_PID=""
if [ "${LLAMA_START:-0}" = "1" ]; then
    LLAMA_PORT="${LLAMA_PORT:-11434}"                   # порт агента (прокси)
    LLAMA_UPSTREAM_PORT="${LLAMA_UPSTREAM_PORT:-11435}" # сам llama-server
    LLAMA_API_KEY="not-needed"   # условный ключ: локальной модели хватает любого
    # Сэмплинг: низкая температура — устойчивость формата инструментов
    # (temp 1.0 давал обрыв после 1-го tool-call: мусорные ответы, ранний EOS);
    # --parallel 1 — один слот: весь контекст и потоки одному запросу агента
    # (иначе 4 слота режут n_ctx_slot до 8192).
    /opt/llama.cpp/llama-server \
        -m /opt/llama.cpp/model.gguf \
        --host 127.0.0.1 --port "$LLAMA_UPSTREAM_PORT" \
        --alias "$(cat /opt/iso/LLAMA_MODEL 2>/dev/null || echo local-model)" \
        -c "${LLAMA_CTX_SIZE:-32768}" \
        -t "${LLAMA_THREADS:-32}" \
        --parallel 1 \
        --temp "${LLAMA_TEMP:-0.2}" --top-p "${LLAMA_TOP_P:-0.9}" \
        --top-k "${LLAMA_TOP_K:-20}" --min-p "${LLAMA_MIN_P:-0.01}" \
        --api-key "$LLAMA_API_KEY" \
        > "$EVIDENCE_DIR/llama_server.log" 2>&1 &
    LLAMA_PID=$!
    ok=0
    for _ in $(seq 1 120); do
        if curl -sf -H "Authorization: Bearer ${LLAMA_API_KEY}" \
                "http://127.0.0.1:${LLAMA_UPSTREAM_PORT}/v1/models" > /dev/null 2>&1; then ok=1; break; fi
        sleep 1
    done
    if [ "$ok" = "1" ]; then
        echo "actor sandbox: llama-server on 127.0.0.1:${LLAMA_UPSTREAM_PORT} (pid ${LLAMA_PID})"
    else
        echo "actor sandbox: WARNING — llama-server не поднялся (см. llama_server.log)"
    fi
    # Прокси: текстовые вызовы инструментов модели -> нативные tool_calls
    # OpenAI (Qwen Code исполняет инструменты только в структурированном виде).
    python3 /opt/iso/llama_tool_proxy.py \
        --listen "$LLAMA_PORT" --upstream "$LLAMA_UPSTREAM_PORT" \
        --log "$EVIDENCE_DIR/tool_proxy.log" &
    PROXY_PID=$!
    ok=0
    for _ in $(seq 1 30); do
        if curl -sf -H "Authorization: Bearer ${LLAMA_API_KEY}" \
                "http://127.0.0.1:${LLAMA_PORT}/v1/models" > /dev/null 2>&1; then ok=1; break; fi
        sleep 1
    done
    if [ "$ok" = "1" ]; then
        echo "actor sandbox: tool proxy on 127.0.0.1:${LLAMA_PORT} (pid ${PROXY_PID})"
    else
        echo "actor sandbox: WARNING — прокси инструментов не поднялся (см. tool_proxy.log)"
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
if [ -n "$LLAMA_PID" ]; then
    kill "$LLAMA_PID" 2>/dev/null || true
    wait "$LLAMA_PID" 2>/dev/null || true
fi
if [ -n "$PROXY_PID" ]; then
    kill "$PROXY_PID" 2>/dev/null || true
    wait "$PROXY_PID" 2>/dev/null || true
fi

echo "actor sandbox: exit_code=${rc}, evidence -> ${EVIDENCE_DIR}"
exit "$rc"
