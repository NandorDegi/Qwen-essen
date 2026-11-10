# Shared helpers. Every phase is idempotent: run it again after a failure.
set -Eeuo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT/config.env"
mkdir -p "$PILOT_HOME" "$PILOT_LOGS"; chmod 700 "$PILOT_HOME"
if [ -f "$PILOT_HOME/env.sh" ]; then source "$PILOT_HOME/env.sh"; fi
log()  { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
ok()   { printf 'OK   %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
# retry N CMD...: the site's internet drops; wait longer each time.
retry() { local n=$1; shift; local i=1; until "$@"; do [ $i -ge $n ] && return 1; log "retry $i/$n in $((i*15)) s: $*"; sleep $((i*15)); i=$((i+1)); done; }
api_key() { cat "$PILOT_HOME/api_key"; }
