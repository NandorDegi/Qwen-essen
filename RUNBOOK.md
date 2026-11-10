# Runbook: install the kit on a DGX Spark by hand

This is the step-by-step install, without Claude Code. With Claude Code, open this directory and
say "deploy the pilot kit"; it follows `CLAUDE.md`, which runs the same steps.

`<spark>` is the ssh name of the Spark. `<user>` is the user on the Spark.

## 0. Before you start

1. On the Spark, check that the user is in the `docker` group: `ssh <spark> 'docker ps'` works
   with no sudo.
2. Make sure that about 150 GB is free in the home directory: `ssh <spark> 'df -h ~'`.
3. Stop other GPU or memory-heavy work on the Spark: `ssh <spark> 'nvidia-smi; free -g'`.

## 1. Make `config.env`

`config.env` holds the pins. It is not in git. Make it from the example on your PC:

```bash
cp config.env.example config.env
```

Fill in these three values. The other values are tested defaults.

| Value | What to put | How to find it |
|---|---|---|
| `MODEL_REPO` | the Hugging Face repository of the Qwen3.8-Flash-Next FP4-Local checkpoint | the model card of the checkpoint you use |
| `MODEL_REVISION` | the commit hash of that repository (pin it; do not use `main`) | `git ls-remote https://huggingface.co/<MODEL_REPO> HEAD` |
| `VLLM_IMAGE` | a vLLM image with the b12x kernels for GB10, as `registry/image:tag@sha256:digest` | `docker buildx imagetools inspect <registry/image:tag>` shows the digest |

> [!warning] The image must be one that the site can pull. A locally built image on another
> machine does not work at the site. If the image is in a private registry, run `docker login`
> on the Spark before phase 20.

Check the ports and the bind address:

- `LLM_BIND=127.0.0.1` keeps the model on the Spark. Set `0.0.0.0` only if the operator's PC must
  use the model; the API key still applies (`LLM_AUTH=key`).
- `LLM_PORT=8000`, `SEARCH_PORT=8888`, `SEARCH_MCP_PORT=8889`, `DSH_WEB_PORT=3080`. Change a port
  if something on the Spark already uses it: `ssh <spark> 'ss -ltn'`.
- Site-only changes can go in `config.local.sh` instead (git ignores it too).

Do not put a key or a password in `config.env`. The kit makes its keys in `~/.config/pilot/`.

## 2. Copy the kit and run the preflight

```bash
rsync -a --delete ./ <spark>:~/pilot-kit/
ssh <spark> 'cd ~/pilot-kit && phases/00-preflight.sh'
```

Continue only when every line is `OK`. A `WARN` needs a decision. A `FAIL` stops the install.

## 3. Start the long phases (at the same time)

Phases 10, 20, 40 and 45 do not depend on each other. Start them detached, so a dropped ssh
session does not stop them:

```bash
for p in 10-model 20-image 40-toolchains 45-search; do
  ssh <spark> "cd ~/pilot-kit && mkdir -p ~/pilot-logs && setsid nohup phases/$p.sh > ~/pilot-logs/$p.log 2>&1 < /dev/null &"
done
```

Check them from time to time (do not keep an ssh session open for hours):

```bash
ssh <spark> 'tail -3 ~/pilot-logs/10-model.log ~/pilot-logs/20-image.log ~/pilot-logs/40-toolchains.log ~/pilot-logs/45-search.log'
```

| Phase | Time | Done when |
|---|---|---|
| `10-model` | 1-3 h | every file size checked, `OK` |
| `20-image` | 15-60 min | image pulled, digest matches, `OK` |
| `40-toolchains` | 10-20 min | `OK`; it can print one sudo line (step 6) |
| `45-search` | 2-5 min | a search returns results, the MCP server lists 4 tools, the engine table |

If a phase stops on the network, run it again. Every phase resumes. After three failures, keep
the last 30 lines of its log and stop.

## 4. Start the model server

Phase 30 needs phases 10 and 20. It uses about 96 GiB of the 121 GiB.

```bash
ssh <spark> 'cd ~/pilot-kit && setsid nohup phases/30-serve.sh > ~/pilot-logs/30-serve.log 2>&1 < /dev/null &'
ssh <spark> 'tail -5 ~/pilot-logs/30-serve.log'
```

The first start compiles kernels: about 10 minutes, allow 40. Done when the log shows the chat
test, the decode speed (about 50 tokens/s) and the tool-call test as `OK`. The container restarts
by itself after a reboot.

> [!warning] If the container stops during the load, read `~/.config/pilot/memguard.log` on the
> Spark. If memguard fired, set `KV_BYTES=5G` in `config.env`, copy the kit again (step 2) and run
> phase 30 again.

## 5. Configure the harnesses

```bash
ssh <spark> 'cd ~/pilot-kit && phases/50-opencode.sh'   # opencode (default)
ssh <spark> 'cd ~/pilot-kit && phases/55-dsh.sh'        # dsh (optional)
```

## 6. The sudo steps (one time, the operator runs them)

The kit uses no sudo. Two optional steps need it:

1. If phase 40 printed a line with `playwright install-deps`, run that line on the Spark. Without
   it, the browser agent cannot start Chromium.
2. For the dsh web UI to start at boot and keep running after logout:
   `sudo loginctl enable-linger <user>`.

## 7. Verify

```bash
ssh <spark> 'cd ~/pilot-kit && phases/60-verify.sh'
```

Done when every line is `OK`: opencode with parallel subagents writes and runs programs in four
languages (Go, Rust, TypeScript, Python), the researcher answers a question with a cited URL, and
the dsh check passes if dsh is installed.

## 8. Use it

- opencode: on the Spark, `cd ~/demo && opencode`. Over ssh: `opencode run "..." < /dev/null`.
- dsh web UI: `ssh -L 3080:127.0.0.1:3080 <spark>`, then open the login URL from
  `ssh <spark> "grep 'dsh web:' ~/pilot-logs/dsh-web.log | tail -1"` (the token changes at each
  start).
- Demos: `DEMOS.md`.

## Operate

| Task | Command (on the Spark) |
|---|---|
| Model server status | `docker ps --filter name=pilot-llm`; `curl -s 127.0.0.1:8000/health` |
| Model server log | `docker logs --tail 50 pilot-llm` |
| Restart the model | `docker restart pilot-llm` (a few minutes after the first start) |
| Search engines that answer now | `cd ~/pilot-kit && phases/45-search.sh test` |
| dsh web UI | `systemctl --user status pilot-dsh.service`; `systemctl --user restart pilot-dsh.service` |
| Memory guard log | `tail ~/.config/pilot/memguard.log` |
| Update a pin | change `config.env`, copy the kit (step 2), run that phase again |

The keys are in `~/.config/pilot/` (mode 600): `api_key` (model server) and
`searxng-secret.env` (search). Never print them, and never copy them into a ticket or a chat.

For other problems, see "Known problems and their fixes" in `CLAUDE.md`.
