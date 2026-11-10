#!/usr/bin/env bash
# Web search on the Spark, no vendor API needed: SearXNG (a metasearch engine) and mcp-searxng (its MCP
# server for the agents). Both are Docker containers on 127.0.0.1 only, read-only, with no capabilities,
# and restart by themselves. Independent of phases 10 and 20: run it in parallel with them.
# Usage: phases/45-search.sh [start|stop|restart|status|test]
source "$(dirname "$0")/lib.sh"
cmd="${1:-start}"
NET=pilot-search; SX=pilot-searxng; MCP=pilot-search-mcp
CONF="$PILOT_HOME/searxng"; SECRET="$PILOT_HOME/searxng-secret.env"
CTL=(python3 -I "$KIT/search/searchctl.py")
URL="http://127.0.0.1:$SEARCH_PORT"; MCP_URL="http://127.0.0.1:$SEARCH_MCP_PORT/mcp"

start() {
  for img in "$SEARXNG_IMAGE" "$MCP_SEARXNG_IMAGE"; do
    docker image inspect "$img" >/dev/null 2>&1 || retry 10 docker pull -q "$img" >/dev/null || fail "pull $img failed; run again"
  done
  ok "images pinned: ${SEARXNG_IMAGE##*/} ${MCP_SEARXNG_IMAGE##*/}"
  # The secret key signs SearXNG's cookies. Made once on this machine; never printed, not in git.
  if [ ! -s "$SECRET" ]; then (umask 077; printf 'SEARXNG_SECRET=%s\n' "$(head -c 48 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 64)" > "$SECRET"); fi
  mkdir -p "$CONF"; chmod 700 "$CONF"
  "${CTL[@]}" render "$KIT/search/settings.yml" "$CONF/settings.yml"
  docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
  docker rm -f "$SX" "$MCP" >/dev/null 2>&1 || true
  # SearXNG runs as this user, so it can read the 600 settings file; FORCE_OWNERSHIP=false stops the
  # entrypoint from trying to chown it.
  docker run -d --name "$SX" --restart unless-stopped --network "$NET" \
    -p "127.0.0.1:$SEARCH_PORT:8080" --user "$(id -u):$(id -g)" \
    --read-only --tmpfs /var/cache/searxng:uid="$(id -u)" --tmpfs /tmp \
    --cap-drop ALL --security-opt no-new-privileges \
    --env-file "$SECRET" -e FORCE_OWNERSHIP=false \
    -v "$CONF:/etc/searxng:ro" "$SEARXNG_IMAGE" >/dev/null
  # The MCP server sends queries only to SEARXNG_URL. web_url_read refuses private addresses (default).
  docker run -d --name "$MCP" --restart unless-stopped --network "$NET" \
    -p "127.0.0.1:$SEARCH_MCP_PORT:$SEARCH_MCP_PORT" \
    --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges \
    -e SEARXNG_URL="http://$SX:8080" -e MCP_HTTP_PORT="$SEARCH_MCP_PORT" -e MCP_HTTP_HOST=0.0.0.0 \
    -e MCP_HTTP_ALLOWED_HOSTS="127.0.0.1:$SEARCH_MCP_PORT,localhost:$SEARCH_MCP_PORT,127.0.0.1,localhost" \
    "$MCP_SEARXNG_IMAGE" >/dev/null
  log "started $SX on $URL and $MCP on $MCP_URL"
  test_search
}

test_search() {
  "${CTL[@]}" wait "$URL" 120 || { docker logs --tail 30 "$SX"; fail "SearXNG does not answer"; }
  for _ in $(seq 1 20); do curl -sf -m 3 "http://127.0.0.1:$SEARCH_MCP_PORT/health" >/dev/null && break; sleep 2; done
  "${CTL[@]}" mcp "$MCP_URL" || { docker logs --tail 30 "$MCP"; fail "MCP handshake"; }
  local rc=0; "${CTL[@]}" engines "$URL" || rc=$?
  [ "$rc" -le 2 ] || fail "engine test"
  ok "web search ready (SearXNG $URL, MCP $MCP_URL)"
}

case "$cmd" in
  start|restart) start ;;
  stop) docker rm -f "$SX" "$MCP" >/dev/null 2>&1 || true; ok "stopped" ;;
  status) docker ps --filter name="$SX" --filter name="$MCP" --format '{{.Names}} {{.Status}} {{.Ports}}' ;;
  test) test_search ;;
  *) fail "usage: $0 start|stop|restart|status|test" ;;
esac
