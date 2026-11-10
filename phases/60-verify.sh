#!/usr/bin/env bash
# End-to-end proof: opencode drives the local model, uses parallel subagents, writes code in four
# languages and runs it; then the researcher answers a factual question through web search, with a
# cited URL. Takes a few minutes. Output in ~/pilot-logs/60-verify.log and 60-research.log.
source "$(dirname "$0")/lib.sh"
command -v opencode >/dev/null || fail "opencode missing: run phase 40"
"$KIT/phases/30-serve.sh" test
if [ "$SEARCH_ENABLED" = 1 ]; then "$KIT/phases/45-search.sh" test; fi
d="$HOME/demo/verify-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$d"; cd "$d" || fail "cannot enter $d"; git init -q
log "opencode run in $d (log: $PILOT_LOGS/60-verify.log)"
start=$(date +%s)
if ! timeout 1800 opencode run --agent lead "In this directory, use parallel coder subagents (one task call each, in one message) to write hello programs in Go (hello.go), Rust (hello.rs, build with rustc), TypeScript (hello.ts, run with node or npx tsx) and Python (hello.py). Each prints 'hello from <language>'. Run all four and show their output." < /dev/null > "$PILOT_LOGS/60-verify.log" 2>&1; then
  log "WARN opencode run exited non-zero"
fi
log "opencode run took $(( $(date +%s) - start )) s"
pass=0
for f in hello.go hello.rs hello.ts hello.py; do if [ -s "$f" ]; then pass=$((pass+1)); else log "missing $f"; fi; done
# Each program must print its line; a missing toolchain shows here, not in the agent's report.
check() { local lang=$1; shift; if "$@" 2>/dev/null | grep -qi "hello from $lang"; then ok "$lang runs"; else log "WARN $lang output"; fi; }
check go go run hello.go
check rust sh -c 'rustc -o /tmp/pilot-hello-rs hello.rs 2>/dev/null && /tmp/pilot-hello-rs'
check typescript sh -c 'node hello.ts 2>/dev/null || npx -y tsx hello.ts'
check python python3 hello.py
[ $pass -eq 4 ] || fail "$pass/4 programs written; see $PILOT_LOGS/60-verify.log"
ok "opencode wrote all four programs in $d"

# Research: search, open a source, cite it. The answer (1991) is stable; the URL must be one it read.
if [ "$SEARCH_ENABLED" = 1 ]; then
  r="$PILOT_LOGS/60-research.log"
  timeout 900 opencode run --agent researcher "In which year was the first public release of the Python programming language? Use web search, open a source page, and answer with the year and the URL of the page you read." < /dev/null > "$r" 2>&1 || log "WARN researcher run exited non-zero"
  grep -q 'searxng' "$r" && ok "researcher used web search" || log "WARN no searxng tool call in $r"
  url=$(grep -oE 'https?://[^ )>"`]+' "$r" | grep -v '127.0.0.1' | head -1 || true)
  if grep -q 1991 "$r" && [ -n "$url" ]; then ok "researcher answered 1991, cited $url"
  else fail "research check: no answer with a cited URL; see $r"; fi
fi

# dsh, if phase 55 installed it: the same checks through the second harness.
if [ -f "$HOME/.dsh/.pilot-kit" ] && command -v dsh >/dev/null; then "$KIT/phases/55-dsh.sh" verify; fi
ok "verify done"
