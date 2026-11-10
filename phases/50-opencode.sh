#!/usr/bin/env bash
# Installs the opencode configuration: provider, agents, commands, MCP servers (Playwright, web
# search from phase 45, Obsidian if configured), KB rules.
# Backs up an existing ~/.config/opencode first. Set OBSIDIAN_MCP_URL in config.env to add the KB.
source "$(dirname "$0")/lib.sh"
OC="$HOME/.config/opencode"
if [ -d "$OC" ] && [ ! -f "$OC/.pilot-kit" ]; then cp -a "$OC" "$OC.bak-$(date +%Y%m%d%H%M%S)"; log "backed up existing $OC"; fi
mkdir -p "$OC/agents" "$OC/commands" "$OC/kb" "$PILOT_LOGS/playwright" "$HOME/demo"
cp "$KIT/opencode/AGENTS.md" "$OC/AGENTS.md"
cp "$KIT/opencode/agents/"*.md "$OC/agents/"
cp "$KIT/opencode/commands/"*.md "$OC/commands/"
cp -r "$KIT/kb/." "$OC/kb/"
obsidian=""
if [ -n "$OBSIDIAN_MCP_URL" ]; then
  # Inline the KB rules into the agent (its prompt is the file body, minus the file's frontmatter).
  python3 - "$OC/agents/kb-scribe.md" "$KIT/kb/KB-AGENT-PROMPT.md" <<'PY'
import re, sys
a, k = sys.argv[1:]
body = re.sub(r"\A---\n.*?\n---\n", "", open(k).read(), flags=re.S)
open(a, "w").write(open(a).read().replace("@KB_PROMPT@", body))
PY
  hdr=""; [ -s "$OBSIDIAN_MCP_TOKEN_FILE" ] && hdr=", \"headers\": { \"Authorization\": \"Bearer {file:$OBSIDIAN_MCP_TOKEN_FILE}\" }"
  obsidian=",
    \"obsidian\": { \"type\": \"remote\", \"url\": \"$OBSIDIAN_MCP_URL\", \"enabled\": true$hdr }"
else
  rm -f "$OC/agents/kb-scribe.md" "$OC/commands/kb.md"
  log "no OBSIDIAN_MCP_URL: kb-scribe and /kb left out"
fi
search=""
if [ "$SEARCH_ENABLED" = 1 ]; then
  search=",
    \"searxng\": { \"type\": \"remote\", \"url\": \"http://127.0.0.1:$SEARCH_MCP_PORT/mcp\", \"enabled\": true }"
else
  log "SEARCH_ENABLED=0: no web search MCP server (researcher keeps webfetch and the browser)"
fi
mode="--headless"; if [ "$PLAYWRIGHT_HEADED" = 1 ]; then mode="--isolated"; fi
python3 - "$KIT/opencode/opencode.json.tmpl" "$OC/opencode.json" <<PY
import json, sys
s = open(sys.argv[1]).read()
for k, v in {"@SERVED_NAME@": "$SERVED_NAME", "@LLM_PORT@": "$LLM_PORT", "@MAX_MODEL_LEN@": "$MAX_MODEL_LEN", "@MAX_OUTPUT@": "$OPENCODE_MAX_OUTPUT",
             "@PILOT_LOGS@": "$PILOT_LOGS", "@PLAYWRIGHT_MODE@": "$mode"}.items():
    s = s.replace(k, v)
s = s.replace("@OBSIDIAN_BLOCK@", '''$obsidian''').replace("@SEARCH_BLOCK@", '''$search''')
json.loads(s)  # refuse to install a config that is not valid JSON
open(sys.argv[2], "w").write(s)
PY
touch "$OC/.pilot-kit"
ok "opencode config in $OC ($(find "$OC/agents" -name '*.md' | wc -l) agents, $(find "$OC/commands" -name '*.md' | wc -l) commands)"
if command -v opencode >/dev/null; then ok "opencode $(opencode --version)"; else log "WARN opencode not on PATH yet: run phase 40"; fi
if command -v playwright-mcp >/dev/null; then ok "playwright-mcp on PATH"; else log "WARN playwright-mcp not on PATH yet: run phase 40"; fi
