# Qwen on one DGX Spark: a local coding-agent kit

A kit that turns one NVIDIA DGX Spark into a self-contained coding-agent workstation:
**opencode** (default) or **dsh** (optional) driving **Qwen3.8-Flash-Next FP4-Local** (125B MoE,
6B active, 262k context, vision, tool calls), served by vLLM on the Spark itself. A lead agent
plans and dispatches parallel subagents; web search is self-hosted. No cloud model, no router, no
vendor account.

It is built for a site that you do not control: one Spark, an unreliable internet connection, no
other infrastructure. Every phase retries, can run again after a failure, and installs in the
user's home and in Docker (no sudo, except one optional step that the phase prints).

## Hardware and software

- NVIDIA DGX Spark (GB10, aarch64, 128 GB unified memory), DGX OS / Ubuntu, Docker with the NVIDIA
  runtime, the user in the `docker` group.
- About 150 GB free in `$HOME` (96 GiB model, ~25 GB image, caches).
- Internet during the installation (Hugging Face, Docker Hub, npm, nodejs.org, go.dev,
  static.rust-lang.org, GitHub). After that, only web search and web fetches use it.
- vLLM needs ~96 GiB of the 121 GiB: stop other GPU or memory-heavy work before phase 30.

## Deploy

The step-by-step install by hand, with every value to fill in, is [`RUNBOOK.md`](RUNBOOK.md).

With Claude Code on a PC that has ssh access to the Spark: open this directory and say "deploy the
pilot kit". It follows `CLAUDE.md`. By hand:

```bash
cp config.env.example config.env        # then fill in MODEL_REPO, MODEL_REVISION, VLLM_IMAGE, check the rest
rsync -a --delete ./ <spark>:~/pilot-kit/
ssh <spark> 'cd ~/pilot-kit && phases/00-preflight.sh'
# then phases 10..60 in order; see the table (10, 20, 40 and 45 can run at the same time)
```

| Phase | What | Time |
|---|---|---|
| `00-preflight` | checks GPU, memory, disk, Docker, tools, network; changes nothing | 1 min |
| `10-model` | downloads the 96 GiB checkpoint (resumable) and checks every file size | 1-3 h |
| `20-image` | pulls the pinned vLLM image (~25 GB) | 15-60 min |
| `30-serve` | starts the model server, waits for health, tests chat, decode speed and a tool call | 20-40 min the first time |
| `40-toolchains` | Node, TypeScript LSP, Python (uv, pyright), Go + gopls, Rust + rust-analyzer, opencode, Playwright MCP + Chromium | 10-20 min |
| `45-search` | web search: SearXNG + its MCP server (Docker, 127.0.0.1 only); prints which engines answer | 2-5 min |
| `50-opencode` | opencode configuration: provider, agents, commands, MCP servers (Playwright, search), KB rules | seconds |
| `55-dsh` | optional: dsh with the same model, roles, skills and MCP servers; web UI as a systemd user service | 2-5 min |
| `60-verify` | opencode + parallel subagents write and run programs in 4 languages; a research question answered with a cited URL; dsh check if installed | 5-15 min |

Configuration is `config.env` (from `config.env.example`): model revision, image digests, tool
versions, ports. Site-specific changes can also go in `config.local.sh` (sourced after
`config.env`; git ignores both). Keys are files in `~/.config/pilot/` (mode 600) and are never
printed: `api_key` (the model server's key, made by phase 30) and `searxng-secret.env` (made by
phase 45).

Ports on the Spark (defaults): model API `LLM_PORT` on `LLM_BIND`; SearXNG `127.0.0.1:8888`;
search MCP `127.0.0.1:8889/mcp`; dsh web UI `127.0.0.1:3080`.

## Use opencode (default)

On the Spark: `cd ~/demo && opencode`. The default agent is `lead`. It plans, and it dispatches
parallel subagents:

| Agent | Role |
|---|---|
| `coder` | implements one unit and proves it works; several run in parallel |
| `tester` | writes and runs tests, reports failures with the exact output |
| `reviewer` | read-only review of a diff |
| `browser-qa` | uses a real Chromium (Playwright MCP) to click through a page and take screenshots |
| `researcher` | searches the web, reads the primary sources (browser for JavaScript pages), cites URLs |
| `explore` | built in, fast read-only code search |
| `kb-scribe` | only with the Obsidian MCP server: writes to the team's knowledge base |

Commands: `/polyglot`, `/scada-twin`, `/ship`, `/review`, `/qa`, `/kb`. Language servers: Python
(pyright), TypeScript, Go (gopls), Rust (rust-analyzer). Over ssh, run `opencode run ... < /dev/null`.

## Use dsh (optional)

Phase 55 installs DeepSeek Harness (`@deepseek-ai/dsh`, MIT) and configures it for the same
server: provider `pilot` (same base URL, model and key as opencode; 262144 context, 65536 reply
cap), one agent preset per role (`lead` is the default; `coder`, `tester`, `reviewer`,
`browser-qa`, `researcher`, started by the lead with the `subagent` tool), the demo procedures
as skills, and the Playwright and search MCP servers. A small plugin (`dsh-pilot-secrets`) refuses
tool calls that read key files or print the environment, and it redacts the model key in tool
results.

- Web UI: `http://127.0.0.1:3080` on the Spark (systemd user unit `pilot-dsh.service`). From the
  operator's PC: `ssh -L 3080:127.0.0.1:3080 <spark>`, then open the login URL with its token,
  which changes at each start: `grep 'dsh web:' ~/pilot-logs/dsh-web.log | tail -1` (the log is
  mode 600). For the
  service to start at boot and keep running after logout: `sudo loginctl enable-linger <user>`.
- One-shot: `dsh --profile headless "run the tests"` (add `--json` for the event stream).
- Limit: dsh cannot allow one tool and deny another per role, so `reviewer`, `researcher` and
  `browser-qa` are read-only by instruction only.

## Web search

`45-search` runs [SearXNG](https://github.com/searxng/searxng), a metasearch engine, and
[mcp-searxng](https://gh.ali360.cloudns.ch/ihor-sokoliuk/mcp-searxng), its MCP server for the agents. Both are
Docker containers, pinned by digest, published on 127.0.0.1 only, with a read-only root file
system and no capabilities, and they restart by themselves. The settings are SearXNG's stock
settings with a broad engine set switched on: general (bing, duckduckgo, mojeek, startpage, qwant,
yahoo, brave, google, wikipedia) and code (github, stackoverflow, arxiv, pypi, npm, docker hub,
mdn). There is no vendor account and no key.

A public search engine can refuse a metasearch server (CAPTCHA, HTTP 429). SearXNG suspends an
engine that refuses and tries it again later. The phase prints a table of the engines that
answered three test queries, and a `WARN` when fewer than three general engines answer. The set
changes from run to run. Measured from one site on 2026-11-10, three runs in 20 minutes: mojeek,
yahoo and google cse answered every time; bing, duckduckgo and brave answered in some runs;
google, qwant and startpage refused every time. Code and package engines (github, stackoverflow,
mdn, docker hub, arxiv, crates.io, pkg.go.dev) answered. Run `phases/45-search.sh test` to see
the current table.

The researcher (and the lead) search with `searxng_web_search`, then read the result pages with
`webfetch` (opencode), `web_fetch` (dsh), `web_url_read` (MCP), or the Playwright browser for pages
that need JavaScript. They cite the URLs of the pages that they read.

## Demos

`DEMOS.md`: polyglot race (four parallel coders, four language servers), plant twin with anomaly
detection and browser QA, screenshot to working page (vision), code review and hardening,
knowledge base (with the Obsidian MCP server), and "it is all local".

## Layout

| Path | What |
|---|---|
| `CLAUDE.md` | the deployment procedure that Claude Code follows |
| `phases/` | the phases, `lib.sh` (shared helpers), `memguard.sh` |
| `opencode/` | `AGENTS.md`, agents, commands, `opencode.json.tmpl` |
| `dsh/` | dsh configuration templates, `render.py`, the `dsh-pilot-secrets` plugin, the systemd unit |
| `search/` | SearXNG settings and `searchctl.py` (checks) |
| `kb/` | rules and templates for an Obsidian knowledge base |
