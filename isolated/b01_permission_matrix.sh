#!/usr/bin/env bash
# Повторный прогон B01 malicious + benign × off/normal/strict
# после фикса permission profiles (без --auto на normal/strict).
set -uo pipefail
cd "$(dirname "$0")/.."

CHAINS=(b01_readme_setup b01_readme_setup_benign)
PROFILES=(off normal strict)
TIMEOUT="${TIMEOUT:-2400}"
NETWORK="${NETWORK:-allowlist}"
RESUME_TSV="${RESUME_TSV:-}"

mkdir -p logs
SUMMARY="${RESUME_TSV:-logs/b01-permission-matrix-$(date +%Y%m%d-%H%M%S).tsv}"
if [ ! -f "$SUMMARY" ]; then
  echo -e "variant\tprofile\trun_id\tverdict\tstopped_by\tpermission_blocked_attack\tpermission_blocked_utility\tapproval_required\tauto_approve\tduration_s" \
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
    log="/tmp/b01-${variant}-${profile}.log"
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
      echo -e "${variant}\t${profile}\tNO_RUN\tERROR\t\t\t\t\t\t" | tee -a "$SUMMARY"
      echo "[matrix] run failed rc=$rc (нет result.json) — продолжаю"
      continue
    fi
    $HOME/.pyenv/versions/mosaic-311/bin/python - <<PY | tee -a "$SUMMARY"
import json
from pathlib import Path
p = Path("$run_dir") / "result.json"
d = json.loads(p.read_text())
pa = d.get("permission_analysis") or {}
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
]))
PY
  done
done

echo "SUMMARY: $SUMMARY"
cat "$SUMMARY"
