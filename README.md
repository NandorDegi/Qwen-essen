# pilot-kit

A local coding agent on one NVIDIA DGX Spark: **opencode** driving **Qwen3.8-Flash-Next
FP4-Local** (125B MoE, 6B active, 262k context, vision, tool calls) served by vLLM on the Spark.
No router, no cloud model.

- Deploy: open Claude Code in this directory on a PC with ssh to the Spark and say
  "deploy the pilot kit" - it follows `CLAUDE.md`. By hand: run `phases/00..60` in order.
- Use: on the Spark, `cd ~/demo && opencode`. The default agent is `lead`, which plans and
  dispatches parallel subagents (`coder`, `tester`, `reviewer`, `browser-qa`, `researcher`,
  `explore`, and `kb-scribe` when the Obsidian MCP server is configured).
- Demos: `DEMOS.md`. Commands: `/polyglot`, `/scada-twin`, `/ship`, `/review`, `/qa`, `/kb`.
- Language servers: Python (pyright), TypeScript, Go (gopls), Rust (rust-analyzer).
- Knowledge base rules for the agent: `kb/`.

Everything is pinned in `config.env` (model revision, image digest, tool versions).
