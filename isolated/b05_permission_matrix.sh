#!/usr/bin/env bash
# B05 malicious + benign × off/normal/strict (OpenCode permission profiles).
set -uo pipefail
cd "$(dirname "$0")/.."

CHAINS=(b05_agent_rules b05_agent_rules_benign)
PROFILES=(off normal strict)
TIMEOUT="${TIMEOUT:-2400}"
NETWORK="${NETWORK:-allowlist}"
RESUME_TSV="${RESUME_TSV:-}"

mkdir -p logs
SUMMARY="${RESUME_TSV:-logs/b05-permission-matrix-$(date +%Y%m%d-%H%M%S).tsv}"
if [ ! -f "$SUMMARY" ]; then
  echo -e "variant\tprofile\trun_id\tverdict\tstopped_by\tpermission_blocked_attack\tpermission_blocked_utility\tapproval_required\tauto_approve\tduration_s\tattack_attempted\tattack_success\tutility_success\ttests_passed\tsecret_read" \
    | tee "$SUMMARY"
fi

already_done() {
  local variant="$1" profile="$2"
  awk -F'\t' -v v="$variant" -v p="$profile" '
    NR>1 && $1==v && $2==p && $4!="" && $4!="ERROR" && $4!="None" && $4!="ERROR_RATE_LIMIT" { found=1 }
    END { exit !found }
  ' "$SUMMARY" 2>/dev/null
}

for chain in "${CHAINS[@]}"; do
  variant=malicious
  [[ "$chain" == *_benign ]] && variant=benign
  for profile in "${PROFILES[@]}"; do
    if already_done "$variant" "$profile"; then
      echo "===== skip $variant / $profile (уже в $SUMMARY) ====="
      continue
    fi
    echo "===== $variant / $profile ====="
    log="/tmp/b05-${variant}-${profile}.log"
    set +e
    ./run_isolated.sh "$chain" \
      --actor opencode \
      --permission-profile "$profile" \
      --network "$NETWORK" \
      --timeout "$TIMEOUT" \
      --verbose 2>&1 | tee "$log"
    rc=${PIPESTATUS[0]}
    set -e
    run_dir=$(ls -td "logs/${chain}-"* 2>/dev/null | head -1 || true)
    if [ -z "$run_dir" ] || [ ! -f "$run_dir/result.json" ]; then
      echo -e "${variant}\t${profile}\tNO_RUN\tERROR\t\t\t\t\t\t\t\t\t\t" | tee -a "$SUMMARY"
      echo "[matrix] run failed rc=$rc (нет result.json) — продолжаю"
      continue
    fi
    $HOME/.pyenv/versions/mosaic-311/bin/python - <<PY | tee -a "$SUMMARY"
import json
from pathlib import Path
p = Path("$run_dir") / "result.json"
d = json.loads(p.read_text())
pa = d.get("permission_analysis") or {}
ba = {}
bap = Path("$run_dir") / "behavior_analysis.json"
if bap.is_file():
    ba = json.loads(bap.read_text())
verdict = str(d.get("verdict") or "ERROR")
blob = ""
for name in ("actor_stderr.log", "actor_stdout.log", "opencode_raw.log"):
    f = Path("$run_dir") / name
    if f.is_file():
        blob += f.read_text(errors="replace")
if "Rate limit exceeded" in blob or "free-models-per-day" in blob:
    verdict = "ERROR_RATE_LIMIT"
print("\t".join([
    "$variant", "$profile", p.parent.name,
    verdict,
    str(pa.get("stopped_by")),
    str(pa.get("permission_blocked_attack")),
    str(pa.get("permission_blocked_utility")),
    str(pa.get("approval_required")),
    str(pa.get("auto_approve")),
    str(d.get("duration_s")),
    str(ba.get("attack_attempted", pa.get("attack_attempted"))),
    str(ba.get("attack_success", pa.get("attack_success"))),
    str(ba.get("utility_success")),
    str(ba.get("tests_passed")),
    str(ba.get("secret_read")),
]))
PY
  done
done

echo "SUMMARY: $SUMMARY"
column -t -s $'\t' "$SUMMARY" 2>/dev/null || cat "$SUMMARY"
