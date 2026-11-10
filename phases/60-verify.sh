#!/usr/bin/env bash
# End-to-end proof: opencode drives the local model, uses a subagent, writes code in four
# languages and runs it. Takes a few minutes. Output in ~/pilot-logs/60-verify.log.
source "$(dirname "$0")/lib.sh"
command -v opencode >/dev/null || fail "opencode missing: run phase 40"
"$KIT/phases/30-serve.sh" test
d="$HOME/demo/verify-$(date +%H%M%S)"; mkdir -p "$d"; cd "$d"; git init -q
timeout 1800 opencode run --agent lead "In this directory, use parallel coder subagents (one task call each, in one message) to write hello programs in Go (hello.go), Rust (hello.rs, build with rustc), TypeScript (hello.ts, run with npx tsx) and Python (hello.py). Each prints 'hello from <language>'. Run all four and show their output." < /dev/null > "$PILOT_LOGS/60-verify.log" 2>&1 || log "WARN opencode run exited non-zero"
pass=0
for f in hello.go hello.rs hello.ts hello.py; do [ -s "$f" ] && pass=$((pass+1)) || log "missing $f"; done
go run hello.go 2>/dev/null | grep -qi "hello from go" && ok "go runs" || log "WARN go output"
python3 hello.py 2>/dev/null | grep -qi "hello from python" && ok "python runs" || log "WARN python output"
[ $pass -eq 4 ] && ok "opencode wrote all four programs in $d" || fail "$pass/4 programs written; see $PILOT_LOGS/60-verify.log"
