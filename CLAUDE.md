# Pilot kit: deploy a local coding agent on the DGX Spark

You are Claude Code on the VizPC. You have ssh access to the pilot DGX Spark (GB10). Your job is
to make that Spark run **opencode with a local Qwen3.8-Flash-Next model**, fully kitted, and to
prove it works. This kit (the directory this file is in) contains everything; you run it on the
Spark over ssh. Work through the phases in order. Do not start a phase until the previous one
printed only `OK` lines (a `WARN` needs a decision; a `FAIL` stops you).

## Ground rules
- Ask the operator for the Spark's ssh name if `SPARK` below is not set. Test it: `ssh $SPARK true`.
- Everything installs in the Spark user's home and in Docker. Do not use sudo unless a phase
  says one sudo step is needed; then show the operator the exact command and let them run it.
- Never print, log or copy the API key (`~/.config/pilot/api_key` on the Spark) or any token.
- The site's internet is unreliable. Every phase retries and is safe to run again. If a phase
  fails on the network, wait a minute and run it again; after three failures, report to the
  operator with the last 30 lines of its log.
- Long phases (10, 20, 30, 40) run detached on the Spark with a log, so a dropped ssh session
  does not kill them. Poll the log; do not hold an ssh session open for an hour.
- Keep a short record of what you did and what you measured in `~/pilot-logs/DEPLOY-NOTES.md`
  on the Spark (date every entry).

## Phases

```bash
SPARK=<ssh name>                                   # e.g. pilot-spark
rsync -a --delete ./ $SPARK:~/pilot-kit/           # or: scp -r . $SPARK:~/pilot-kit
ssh $SPARK 'cd ~/pilot-kit && phases/00-preflight.sh'
```

| Phase | What | Run as | Time |
|---|---|---|---|
| 00-preflight | checks GPU, memory, disk, Docker, network; changes nothing | foreground | 1 min |
| 10-model | downloads the 96 GiB checkpoint (resumable) and verifies every file size | detached | 1-3 h |
| 20-image | pulls the pinned vLLM image (~25 GB) | detached, in parallel with 10 | 15-60 min |
| 30-serve | starts the model server, waits for health, tests chat + a tool call | detached | 20-40 min first time |
| 40-toolchains | Node, TypeScript LSP, Python (uv, pyright), Go + gopls, Rust + rust-analyzer, opencode, Chromium | detached, in parallel with 10 | 10-20 min |
| 50-opencode | installs the opencode config: provider, 6-7 agents, commands, Playwright MCP, KB rules | foreground | seconds |
| 60-verify | opencode + subagents write and run programs in 4 languages | foreground | 5-15 min |

Detached form (replace NN-name):
```bash
ssh $SPARK 'cd ~/pilot-kit && mkdir -p ~/pilot-logs && setsid nohup phases/NN-name.sh > ~/pilot-logs/NN-name.log 2>&1 < /dev/null &'
ssh $SPARK 'tail -5 ~/pilot-logs/NN-name.log'
```
Phases 10, 20 and 40 are independent: start them together. Phase 30 needs 10 and 20.
Phase 60 needs 30, 40 and 50.

## Before phase 30
- Stop every other GPU or memory-heavy process on the Spark (`nvidia-smi`, `free -g`). vLLM needs
  ~96 GiB of the 121: weights, a fixed 7 GiB K/V pool (`KV_BYTES`) and runtime. Measured on a GB10
  (2026-10-30): lowest MemAvailable during boot 17 GiB, 25 GiB while serving. Without
  `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` the boot-time weight repack fragments and
  MemAvailable falls to 1-4 GiB whatever `GPU_MEM` says; do not remove it.
- `phases/memguard.sh` stops the container if MemAvailable falls below `GUARD_GIB` (4), so the model
  and not the desktop is what goes. Its log is `~/.config/pilot/memguard.log`. If it fires, lower
  `KV_BYTES` (for example `5G`), rsync again, and rerun phase 30.
- The first start compiles and autotunes kernels (about 10 min measured, allow 40; `VLLM_ENGINE_READY_TIMEOUT_S=3600`).
  This is normal. Later restarts take a few minutes. The container restarts by itself after a
  reboot (`--restart unless-stopped`).

## Known problems and their fixes
| Symptom | Cause | Fix |
|---|---|---|
| download stops growing, no error | the hub's xet backend stalls | the kit sets `HF_HUB_DISABLE_XET=1`; kill the phase by pid, run it again (it resumes) |
| `401` from the model | the client has no key | opencode reads `PILOT_LLM_KEY` from `~/.config/pilot/env.sh`; open a new shell |
| tool call arrives as text with `<tool_call>` | wrong parser | the server must run `--tool-call-parser qwen3_xml` (it does in phase 30) |
| opencode answers, but agents do not run tools | the model id in opencode.json does not match `--served-model-name` | rerun phase 50 |
| Chromium fails to start in browser-qa | missing system libraries | phase 40 prints one `sudo npx playwright install-deps chromium` line for the operator |
| container exits at load | out of memory, or memguard fired | read `~/.config/pilot/memguard.log`; stop other processes; lower `KV_BYTES` |
| `opencode run` over ssh hangs after `init` | it waits for stdin | always run it with `< /dev/null` |

## When you are done
Report to the operator: each phase's result, the decode speed from phase 30's chat test, the
phase 60 result, and anything that needed a decision. Then point them to `DEMOS.md`.

## Optional: the Obsidian knowledge base
If the operator gives you the URL (and token, if any) of the Obsidian MCP server on the PC next
to the Spark: put the URL in `OBSIDIAN_MCP_URL` in `config.env`; write the token to
`~/.config/pilot/obsidian_token` on the Spark (mode 600, never echo it); rerun phase 50. That adds
the `kb-scribe` agent and the `/kb` command. `kb/MIGRATION.md` is the procedure to bring their
existing vault up to the standard in `kb/` - run it only with the operator's approval, in small
batches.
