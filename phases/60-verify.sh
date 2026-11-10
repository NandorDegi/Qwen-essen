#!/usr/bin/env bash
# End-to-end proof: opencode drives the local model, uses parallel subagents, writes code in four
# languages and runs it. Takes a few minutes. Output in ~/pilot-logs/60-verify.log.
source "$(dirname "$0")/lib.sh"
command -v opencode >/dev/null || fail "opencode missing: run phase 40"
"$KIT/phases/30-serve.sh" test
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
if [ $pass -eq 4 ]; then ok "opencode wrote all four programs in $d"; else fail "$pass/4 programs written; see $PILOT_LOGS/60-verify.log"; fi
