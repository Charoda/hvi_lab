#!/usr/bin/env bash
# Обёртка OpenCode для изолированного прогона.
#
# OFF (OPENCODE_AUTO=1):  opencode run --auto — fully permissive baseline.
# NORMAL/STRICT (OPENCODE_AUTO=0): без --auto. Headless ask → approval_required,
#   процесс убивается БЕЗ аппрува (действие не выполняется).
#
# Артефакты:
#   $EVIDENCE_DIR/permission_events.jsonl
#   $EVIDENCE_DIR/opencode_raw.log

set -u

EVIDENCE_DIR="${EVIDENCE_DIR:-/evidence}"
AUTO="${OPENCODE_AUTO:-0}"
MODEL="${OPENCODE_MODEL:?OPENCODE_MODEL required}"
PROMPT="${AGENT_PROMPT:?AGENT_PROMPT required}"
EVENTS="${EVIDENCE_DIR}/permission_events.jsonl"
RAW="${EVIDENCE_DIR}/opencode_raw.log"
ASK_IDLE_SECS="${OPENCODE_ASK_IDLE_SECS:-8}"

mkdir -p "$EVIDENCE_DIR"
: > "$EVENTS"
: > "$RAW"

emit_event() {
    local kind="$1"
    # Важно: "${2:-{}}" в bash даёт лишнюю "}" → ломает JSON.
    local detail="${2:-"{}"}"
    KIND="$kind" DETAIL="$detail" EVENTS="$EVENTS" python3 - <<'PY'
import json, os, datetime
ev = {
    "ts": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "kind": os.environ["KIND"],
    "detail": json.loads(os.environ["DETAIL"]),
}
with open(os.environ["EVENTS"], "a", encoding="utf-8") as f:
    f.write(json.dumps(ev, ensure_ascii=False) + "\n")
PY
}

json_escape() {
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()[:800]))' 2>/dev/null || \
        printf '"%s"' "$(cat | tr -d '\n' | sed 's/"/\\"/g' | cut -c1-800)"
}

if [ "$AUTO" = "1" ] || [ "$AUTO" = "true" ] || [ "$AUTO" = "yes" ]; then
    emit_event "auto_mode" '{"enabled":true,"flag":"--auto"}'
    # stdout/stderr попадут в actor_*.log через entrypoint.
    opencode run --dir . --title mosaic-iso -m "$MODEL" --auto "$PROMPT"
    exit $?
fi

emit_event "auto_mode" '{"enabled":false,"flag":null}'

OUT="${EVIDENCE_DIR}/.opencode_stdout.tmp"
ERR="${EVIDENCE_DIR}/.opencode_stderr.tmp"
: > "$OUT"
: > "$ERR"

opencode run --dir . --title mosaic-iso -m "$MODEL" \
    --print-logs --log-level INFO --format json \
    "$PROMPT" >"$OUT" 2>"$ERR" &
OC_PID=$!

ASK_HIT=0
ASK_AT=0
while kill -0 "$OC_PID" 2>/dev/null; do
    # Сырой лог для пост-анализа
    cat "$OUT" "$ERR" > "$RAW" 2>/dev/null || true

    if grep -Eiq 'message=asking|waiting for permission|requires approval|"permission\.ask"|permission ask' "$ERR" "$OUT" 2>/dev/null; then
        if [ "$ASK_HIT" -eq 0 ]; then
            ASK_HIT=1
            ASK_AT="$(date +%s)"
            line="$(grep -Ei 'message=asking|permission|approval' "$ERR" "$OUT" 2>/dev/null | tail -1 | json_escape)"
            emit_event "approval_required" "{\"source\":\"watchdog\",\"line\":${line}}"
        fi
        now="$(date +%s)"
        if [ $((now - ASK_AT)) -ge "$ASK_IDLE_SECS" ]; then
            emit_event "ask_aborted" "{\"reason\":\"headless_ask_no_auto_approve\",\"pid\":${OC_PID}}"
            kill -TERM "$OC_PID" 2>/dev/null || true
            sleep 2
            kill -KILL "$OC_PID" 2>/dev/null || true
            break
        fi
    fi
    sleep 1
done

wait "$OC_PID" 2>/dev/null
rc=$?
cat "$OUT" "$ERR" > "$RAW" 2>/dev/null || true

# Пробросим вывод агента в stdout/stderr обёртки → actor_*.log
cat "$OUT" 2>/dev/null || true
cat "$ERR" >&2 2>/dev/null || true

# Явные deny (strict / tool reject) — отдельный kind.
if grep -Eiq 'prevents you from using this specific tool call' "$RAW" 2>/dev/null; then
    while IFS= read -r line; do
        esc="$(printf '%s' "$line" | json_escape)"
        emit_event "deny" "{\"source\":\"opencode_log\",\"line\":${esc}}"
    done < <(grep -Ei 'prevents you from using this specific tool call' "$RAW" | head -50)
fi

rm -f "$OUT" "$ERR"

if [ "$ASK_HIT" -eq 1 ]; then
    exit 75
fi
exit "$rc"
