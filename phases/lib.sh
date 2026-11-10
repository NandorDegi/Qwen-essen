# shellcheck shell=bash
# Shared helpers. Every phase is idempotent: run it again after a failure.
set -Eeuo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log()  { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
ok()   { printf 'OK   %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

[ -f "$KIT/config.env" ] || fail "$KIT/config.env missing: copy config.env.example to config.env and fill it in"
# shellcheck source=/dev/null
source "$KIT/config.env"
# Optional overrides, never committed: config.local.sh next to config.env (site changes), or the
# file PILOT_OVERRIDES names (for example a test against a model server that already runs).
# shellcheck source=/dev/null
if [ -f "$KIT/config.local.sh" ]; then source "$KIT/config.local.sh"; fi
# shellcheck source=/dev/null
if [ -n "${PILOT_OVERRIDES:-}" ]; then source "$PILOT_OVERRIDES"; fi

# Settings added after the first pilot. config.env can set each of them; these are the defaults.
: "${OBSIDIAN_MCP_URL:=}" "${OBSIDIAN_MCP_TOKEN_FILE:=$HOME/.config/pilot/obsidian_token}"
: "${PLAYWRIGHT_HEADED:=0}" "${GOPLS_VERSION:=v0.24.0}" "${RUST_TOOLCHAIN:=stable}"
: "${DSH_VERSION:=0.2.2-rc.1}" "${DSH_WEB_HOST:=127.0.0.1}" "${DSH_WEB_PORT:=3080}" "${DSH_SYSTEMD:=1}"
: "${OPENCODE_MAX_OUTPUT:=65536}"

for v in PILOT_HOME PILOT_LOGS MODEL_REPO MODEL_REVISION MODEL_DIR VLLM_IMAGE CONTAINER \
         LLM_BIND LLM_PORT LLM_AUTH SERVED_NAME MAX_MODEL_LEN MAX_SEQS KV_BYTES GPU_MEM MTP_TOKENS GUARD_GIB \
         NODE_VERSION GO_VERSION OPENCODE_VERSION TYPESCRIPT_VERSION TSLS_VERSION PYRIGHT_VERSION PLAYWRIGHT_MCP_VERSION; do
  [ -n "${!v:-}" ] || fail "config.env does not set $v (see config.env.example)"
done

mkdir -p "$PILOT_HOME" "$PILOT_LOGS"; chmod 700 "$PILOT_HOME"
# shellcheck source=/dev/null
if [ -f "$PILOT_HOME/env.sh" ]; then source "$PILOT_HOME/env.sh"; fi
# retry N CMD...: the site's internet drops; wait longer each time.
retry() { local n=$1; shift; local i=1; until "$@"; do [ "$i" -ge "$n" ] && return 1; log "retry $i/$n in $((i*15)) s: $*"; sleep $((i*15)); i=$((i+1)); done; }
KEY_FILE="$PILOT_HOME/api_key"
api_key() { cat "$KEY_FILE"; }
