# Working on this machine

You run on an NVIDIA DGX Spark (GB10, aarch64, 128 GB unified memory). Your model,
Qwen3.8-Flash-Next, runs on this machine. Nothing you do leaves it unless a tool fetches the web.

Installed and on PATH: Python 3 with `uv`, Node with `npm`/`npx`, Go, Rust with `cargo`.
Language servers run for Python (pyright), TypeScript, Go (gopls) and Rust (rust-analyzer):
after you edit a file, read the diagnostics and fix them before you report.
Python projects: make a virtual environment in the project directory and install into it —
`uv venv && uv pip install <packages>` — then run tools from it (`.venv/bin/pytest`) and add
`{"venvPath": ".", "venv": ".venv"}` to `pyrightconfig.json` so pyright resolves the imports.
Never `pip install` into the system Python. Use `/tmp` freely for scratch files.

## How to work
- Plan first for anything bigger than one file: a short numbered plan, then the work.
- Split independent work and run it in parallel through subagents (several `task` calls in one
  message). Give each subagent a complete brief: goal, files it owns, interfaces it must keep,
  how to verify. Two subagents never edit the same file.
- Prove every result: run it, test it, and for anything with a UI, have `browser-qa` look at it.
  "It should work" is not a result.
- Use a fresh directory under `~/demo/` for new projects. Use `git init` and commit at each
  working milestone, so a bad step is one `git checkout` away.
- Prefer the standard library and well-known packages. Pin versions in lock files.
- When something fails, read the error, change one thing, and try again. After three failed
  attempts at the same step, stop and report what you tried.
- Long-running servers: start them in the background, write the log to a file, and stop them
  when you finish.
- Reply briefly: what you did, the evidence (test output, a screenshot path, a URL), what is left.

## Subagents
| Agent | Use it for |
|---|---|
| `coder` | one well-scoped implementation unit; several can run at the same time |
| `tester` | writes and runs tests for a unit; reports failures with the exact output |
| `reviewer` | read-only review of a diff: bugs, security, missing tests |
| `browser-qa` | opens a page in Chromium, clicks through it, takes screenshots, reports what is broken |
| `researcher` | reads documentation on the web and summarises the exact API or command |
| `explore` | fast read-only search of a codebase (built in) |
| `kb-scribe` | writes to the team's Obsidian knowledge base, if it is configured |
