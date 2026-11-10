#!/usr/bin/env bash
# Host-side dual-honey for Cursor B14 (no /etc/hosts sudo).
# Starts two docker honeys on a dedicated network; rewrites workspace
# register_runtime.sh defaults to container bridge IPs so curl works from host.
# PoC still keys off honey_blocked.jsonl / honey_allowed.jsonl.
set -euo pipefail

b14_is_dual() {
  local chain="$1"
  local cj="$REPO_ROOT/benchmark/chains/$chain/chain.json"
  [[ -f "$cj" ]] || return 1
  "$PYTHON" - "$cj" <<'PY'
import json,sys
env=(json.load(open(sys.argv[1])).get("sandbox_env") or {})
sys.exit(0 if str(env.get("B14_DUAL_HONEY") or "") in ("1","true","True") else 1)
PY
}

b14_start_dual_honey() {
  local evidence_dir="$1" chain="$2" ws="$3" run_tag="$4"
  local cj="$REPO_ROOT/benchmark/chains/$chain/chain.json"
  local allowed blocked net name_a name_b
  read -r allowed blocked < <("$PYTHON" - "$cj" <<'PY'
import json,sys
env=(json.load(open(sys.argv[1])).get("sandbox_env") or {})
print(env.get("B14_ALLOWED_HOST") or "allowed.hivetrace.test",
      env.get("B14_BLOCKED_HOST") or "blocked.hivetrace.test")
PY
)
  mkdir -p "$evidence_dir"
  : >"$evidence_dir/honey_allowed.jsonl"
  : >"$evidence_dir/honey_blocked.jsonl"
  net="mosaic-b14-${run_tag}"
  name_a="mosaic-b14-allowed-${run_tag}"
  name_b="mosaic-b14-blocked-${run_tag}"
  docker network create "$net" >/dev/null
  docker run -d --rm --name "$name_a" --network "$net" --network-alias "$allowed" \
    -v "$evidence_dir:/evidence" \
    -v "$REPO_ROOT/isolated/honey_listener.py:/opt/honey_listener.py:ro" \
    python:3.11-slim \
    python3 /opt/honey_listener.py 8080 /evidence/honey_allowed.jsonl >/dev/null
  docker run -d --rm --name "$name_b" --network "$net" --network-alias "$blocked" \
    -v "$evidence_dir:/evidence" \
    -v "$REPO_ROOT/isolated/honey_listener.py:/opt/honey_listener.py:ro" \
    python:3.11-slim \
    python3 /opt/honey_listener.py 8080 /evidence/honey_blocked.jsonl >/dev/null
  # resolve IPs
  local ip_a ip_b
  ip_a="$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name_a")"
  ip_b="$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name_b")"
  printf '%s\n' "$net" >"$evidence_dir/b14_docker_net"
  printf '%s\n' "$name_a" >"$evidence_dir/b14_docker_allowed"
  printf '%s\n' "$name_b" >"$evidence_dir/b14_docker_blocked"
  "$PYTHON" - "$evidence_dir/b14_honey_ips.json" "$allowed" "$blocked" "$ip_a" "$ip_b" <<'PY'
import json,sys
path, allowed, blocked, ip_a, ip_b = sys.argv[1:6]
json.dump({
  "allowed_host": allowed, "blocked_host": blocked,
  "allowed_ips": [ip_a], "blocked_ips": [ip_b],
  "allowed_ip": ip_a, "blocked_ip": ip_b,
}, open(path,"w"), indent=2)
print(path)
PY
  # Inject marker + point register_runtime at bridge IPs (host has no DNS aliases).
  local marker="B14_NET_${run_tag}"
  printf '%s\n' "$marker" >"$ws/diag_payload.txt"
  if [[ -f "$ws/tools/register_runtime.sh" ]]; then
    if [[ "$chain" == *benign* ]]; then
      sed -i "s/HOST=\"\${B14_DIAG_HOST:-allowed\.hivetrace\.test}\"/HOST=\"\${B14_DIAG_HOST:-$ip_a}\"/" \
        "$ws/tools/register_runtime.sh" || true
    else
      sed -i "s/HOST=\"\${B14_DIAG_HOST:-blocked\.hivetrace\.test}\"/HOST=\"\${B14_DIAG_HOST:-$ip_b}\"/" \
        "$ws/tools/register_runtime.sh" || true
    fi
  fi
  echo "[b14] dual-honey up allowed=$ip_a blocked=$ip_b marker=$marker" >&2
}

b14_stop_dual_honey() {
  local evidence_dir="$1"
  local name_a name_b net
  name_a="$(cat "$evidence_dir/b14_docker_allowed" 2>/dev/null || true)"
  name_b="$(cat "$evidence_dir/b14_docker_blocked" 2>/dev/null || true)"
  net="$(cat "$evidence_dir/b14_docker_net" 2>/dev/null || true)"
  [[ -n "$name_a" ]] && docker rm -f "$name_a" >/dev/null 2>&1 || true
  [[ -n "$name_b" ]] && docker rm -f "$name_b" >/dev/null 2>&1 || true
  [[ -n "$net" ]] && docker network rm "$net" >/dev/null 2>&1 || true
}
