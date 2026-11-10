#!/usr/bin/env bash
# Installs the opencode configuration: provider, agents, commands, MCP servers, KB rules.
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
mode="--headless"; [ "${PLAYWRIGHT_HEADED:-0}" = 1 ] && mode="--isolated"
python3 - "$KIT/opencode/opencode.json.tmpl" "$OC/opencode.json" <<PY
import json, sys
s = open(sys.argv[1]).read()
for k, v in {"@SERVED_NAME@": "$SERVED_NAME", "@LLM_PORT@": "$LLM_PORT", "@MAX_MODEL_LEN@": "$MAX_MODEL_LEN",
             "@HOME@": "$HOME", "@PLAYWRIGHT_MODE@": "$mode"}.items():
    s = s.replace(k, v)
s = s.replace("@OBSIDIAN_BLOCK@", '''$obsidian''')
json.loads(s)  # refuse to install a config that is not valid JSON
open(sys.argv[2], "w").write(s)
PY
touch "$OC/.pilot-kit"
ok "opencode config in $OC ($(ls "$OC/agents" | wc -l) agents, $(ls "$OC/commands" | wc -l) commands)"
command -v opencode >/dev/null && opencode --version >/dev/null && ok "opencode $(opencode --version)" || log "WARN opencode not on PATH yet: run phase 40"
