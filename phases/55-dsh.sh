#!/usr/bin/env bash
# Optional second harness: DeepSeek Harness (dsh) with the same local model, roles, skills and MCP
# servers as opencode, and its web UI as a systemd --user service on DSH_WEB_HOST:DSH_WEB_PORT
# (127.0.0.1:3080 by default). opencode stays the default; this phase changes nothing of it.
# Backs up an existing ~/.dsh first. Needs phase 40 (Node) and 50; uses phase 45 if SEARCH_ENABLED=1.
# Usage: phases/55-dsh.sh [install|verify]   (default: install, then verify)
source "$(dirname "$0")/lib.sh"
cmd="${1:-all}"
export DSH_HOME="$HOME/.dsh" DSH_AGENTS_HOME="$HOME/.agents"
UNIT=pilot-dsh.service; UNIT_FILE="$HOME/.config/systemd/user/$UNIT"
WEB_URL="http://$DSH_WEB_HOST:$DSH_WEB_PORT"

install() {
  command -v node >/dev/null || fail "node missing: run phase 40"
  node -e 'const [a,b]=process.versions.node.split(".").map(Number); process.exit(a>24||(a===24&&b>=9)?0:1)' \
    || fail "dsh needs Node >= 24.9; node is $(node --version) (NODE_VERSION in config.env)"
  if [ "$(dsh --version 2>/dev/null || true)" != "$DSH_VERSION" ]; then
    retry 5 npm install -g --no-fund --no-audit "@deepseek-ai/dsh@$DSH_VERSION" >/dev/null || fail "npm install dsh failed; run again"
    hash -r
  fi
  ok "dsh $(dsh --version)"
  if [ -d "$DSH_HOME" ] && [ ! -f "$DSH_HOME/.pilot-kit" ] && [ -n "$(ls -A "$DSH_HOME" 2>/dev/null)" ]; then
    cp -a "$DSH_HOME" "$DSH_HOME.bak-$(date +%Y%m%d%H%M%S)"; log "backed up existing $DSH_HOME"
  fi
  mkdir -p "$DSH_HOME/plugins" "$PILOT_LOGS/playwright" "$HOME/demo"
  rm -rf "$DSH_HOME/plugins/dsh-pilot-secrets"; cp -r "$KIT/dsh/plugins/dsh-pilot-secrets" "$DSH_HOME/plugins/"
  PLAYWRIGHT_MODE="--headless"; if [ "$PLAYWRIGHT_HEADED" = 1 ]; then PLAYWRIGHT_MODE="--isolated"; fi
  export LLM_PORT SERVED_NAME MAX_MODEL_LEN MAX_SEQS PILOT_LOGS OPENCODE_MAX_OUTPUT SEARCH_ENABLED SEARCH_MCP_PORT PLAYWRIGHT_MODE
  ok "dsh config: $(python3 -I "$KIT/dsh/render.py" "$KIT" "$DSH_HOME")"
  # The local plugin is linked into each profile, as `pnpm install` would do; no registry needed.
  for p in web headless; do
    mkdir -p "$DSH_HOME/profiles/$p/node_modules"
    ln -sfn "$DSH_HOME/plugins/dsh-pilot-secrets" "$DSH_HOME/profiles/$p/node_modules/dsh-pilot-secrets"
    [ -f "$DSH_HOME/profiles/$p/cordis.yml" ] || printf '# dsh profile root: the tree is composed from package.json bundles and cordis.patch.yml.\n[]\n' > "$DSH_HOME/profiles/$p/cordis.yml"
  done
  [ -f "$DSH_HOME/profiles/headless/cordis.patch.yml" ] || printf '[]\n' > "$DSH_HOME/profiles/headless/cordis.patch.yml"
  touch "$DSH_HOME/.pilot-kit"

  if [ "$DSH_SYSTEMD" = 1 ]; then
    mkdir -p "$(dirname "$UNIT_FILE")"
    sed -e "s/@HOST@/$DSH_WEB_HOST/g" -e "s/@PORT@/$DSH_WEB_PORT/g" -e "s#@LOG@#$PILOT_LOGS/dsh-web.log#g" \
      "$KIT/dsh/pilot-dsh.service.tmpl" > "$UNIT_FILE"
    systemctl --user daemon-reload
    systemctl --user enable "$UNIT" >/dev/null 2>&1 || true
    systemctl --user restart "$UNIT"
    ok "systemd --user unit $UNIT ($WEB_URL)"
    loginctl show-user "$USER" -p Linger 2>/dev/null | grep -q yes \
      || log "WARN the web UI stops at logout and does not start at boot until lingering is on: sudo loginctl enable-linger $USER"
  else
    log "DSH_SYSTEMD=0: no systemd unit; start the web UI by hand: dsh web --no-open --host $DSH_WEB_HOST --port $DSH_WEB_PORT"
  fi
}

# Web UI: the unit's server, or (DSH_SYSTEMD=0) a short-lived one on the same port. The server
# prints a login URL with a token into its log (mode 600); this check uses it and never prints it.
check_web() {
  local pid="" weblog="$PILOT_LOGS/dsh-web.log"
  if [ "$DSH_SYSTEMD" != 1 ]; then
    weblog="$PILOT_LOGS/55-dsh-web.log"; (umask 077; : > "$weblog")
    (cd "$HOME/demo" && exec dsh web --no-open --host "$DSH_WEB_HOST" --port "$DSH_WEB_PORT") >> "$weblog" 2>&1 < /dev/null &
    pid=$!
  fi
  local code=000 login="" lcode=000
  for _ in $(seq 1 60); do
    code=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$WEB_URL/" || true)
    case "$code" in 200|30?|401) break ;; esac
    sleep 2
  done
  login=$(grep -oE "dsh web: http[^ ]*token=[^ ]+" "$weblog" 2>/dev/null | tail -1 | cut -d' ' -f3 || true)
  if [ -n "$login" ]; then   # the token buys a signed cookie, then a redirect to the page
    local jar; jar=$(umask 077; mktemp)
    lcode=$(curl -s -o /dev/null -m 10 -w '%{http_code}' -c "$jar" -b "$jar" -L "$login" || true); rm -f "$jar"
  fi
  if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  if [ "$lcode" != 200 ] && [ "$code" != 200 ]; then
    sed -E 's/token=[^ &]+/token=<redacted>/g' "$weblog" 2>/dev/null | tail -20
    fail "dsh web UI on $WEB_URL: HTTP $code, login HTTP $lcode"
  fi
  if grep -qiE 'preset.*(fail|error)|failed to (load|mount)|MISSING_CREDENTIAL' "$weblog" 2>/dev/null; then
    log "WARN the web profile logged a load problem; see $weblog"
  fi
  ok "dsh web UI answers on $WEB_URL (login URL with its token: grep 'dsh web:' $weblog)"
}

# One headless run that must call tools against the local model; the JSON event stream is the evidence.
headless() { # NAME TASK
  local log="$PILOT_LOGS/55-dsh-$1.jsonl"
  timeout 900 dsh --profile headless --json "$2" < /dev/null > "$log" 2> "$log.err" || log "WARN dsh headless ($1) exited non-zero"
  echo "$log"
}

verify() {
  command -v dsh >/dev/null || fail "dsh missing: run phase 55 install"
  [ -s "$KEY_FILE" ] || [ "$LLM_AUTH" = none ] || fail "no $KEY_FILE: run phase 30 first"
  check_web
  local d; d="$HOME/demo/dsh-verify-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$d"; cd "$d" || fail "cannot enter $d"; git init -q
  local start; start=$(date +%s)
  local j; j=$(headless tools "Write a Python file hello.py that prints 'hello from dsh', run it with python3, and reply with its output.")
  python3 -I - "$j" <<'PY' || fail "dsh headless: no tool call; see $j and $j.err"
import json, sys
ev = [json.loads(l) for l in open(sys.argv[1]) if l.strip().startswith("{")]
calls = [e for e in ev if e.get("type") == "tool_call"]
final = next((e for e in ev if e.get("type") == "final"), {})
names = sorted({(c.get("name") or c.get("tool") or "?") for c in calls})
print(f"OK   dsh headless: {len(calls)} tool calls {names}; final: {str(final.get('text') or final.get('answer') or '')[:60]!r}")
sys.exit(0 if calls else 1)
PY
  if python3 hello.py 2>/dev/null | grep -q "hello from dsh"; then ok "dsh wrote and ran hello.py in $d ($(( $(date +%s) - start )) s)"
  else fail "hello.py missing or wrong in $d; see $j"; fi
  if [ "$SEARCH_ENABLED" = 1 ]; then
    j=$(headless research "In which year was the first public release of the Python programming language? Use web search (searxng_web_search), open a source page, and answer with the year and the URL of the page you read.")
    grep -q 'searxng' "$j" && ok "dsh used web search" || log "WARN no searxng tool call in $j"
    local url; url=$(python3 -I -c 'import json,sys; print(next((e.get("text") or "" for e in map(json.loads, filter(str.strip, open(sys.argv[1]))) if e.get("type")=="final"), ""))' "$j" | grep -oE 'https?://[^ )>"`]+' | grep -v 127.0.0.1 | head -1 || true)
    if grep -q 1991 "$j" && [ -n "$url" ]; then ok "dsh research: 1991, cited $url"; else fail "dsh research check: no answer with a cited URL; see $j"; fi
  fi
}

case "$cmd" in
  all) install; verify ;;
  install) install ;;
  verify) verify ;;
  *) fail "usage: $0 [install|verify]" ;;
esac
