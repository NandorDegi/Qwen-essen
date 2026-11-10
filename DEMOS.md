# Demo script

Everything runs on the Spark: `cd ~/demo && opencode`. Show `nvidia-smi` and the network
indicator once at the start, so the audience knows nothing goes to a cloud model.
Rehearse each demo once on the day; the model is fast but not instant (expect ~40 tok/s and
20-60 s per large step). Start a fresh opencode session per demo (`/new`).

## 1. Polyglot race (subagents + four language servers) — 8-15 min
`/polyglot`
- Four `coder` subagents start in parallel, one per language (Go, Rust, TypeScript, Python).
  Open the subagent views to show them working at the same time.
- Point out the language-server diagnostics being fixed before each coder reports.
- The lead cross-checks all four for identical answers and error handling, then benchmarks them.
- Ends with a comparison table. Talking point: one local model, a team of agents, four stacks.

## 2. Plant twin with anomaly detection (industrial story) — 15-25 min
`/scada-twin`
- Python simulator, Go detector service, TypeScript dashboard built in parallel against an
  interface the lead defines first.
- `browser-qa` opens the dashboard in Chromium, waits for the injected faults and screenshots
  the alarms. Show the screenshots (`~/pilot-logs/playwright/`).
- Variation for the audience: "add a fifth tank and an alarm for pump cavitation" with `/ship`.

## 3. Screenshot to working page (vision) — 5-10 min
Drop a screenshot or a photo of a whiteboard sketch into the opencode prompt, then:
"Build this page in ~/demo/page with Vite + TypeScript, start it, and have browser-qa compare
it with the image. Iterate until it matches."

## 4. Code review and hardening — 5 min
In any repository (one of the demo projects, or a customer sample):
`/review` — the reviewer and tester run in parallel, read-only; then "fix the top three".

## 5. Knowledge base (only with the Obsidian MCP server) — 5 min
`/kb document the plant twin: architecture, the two detectors, how to run it, and the decision
to use z-score detection instead of a trained model`
- `kb-scribe` searches the vault first, writes in the right layer with the house writing
  standard, adds a decision record and a log entry. Open the notes in Obsidian live.

## 6. "It is all local" — 1 min
During any long step, unplug the network (or `nmcli networking off`). The agents keep working.
Only `researcher` web lookups stop.

## If something goes wrong
- A step stalls for minutes: press Esc, then "continue" — the lead resumes from its todo list.
- A subagent loops: stop it, tell the lead "take that part over yourself".
- The model server: `~/pilot-kit/phases/30-serve.sh status`, then `restart` (a few minutes).
