#!/usr/bin/env bash
# Starts the model server (vLLM b12x) and proves it: health, a chat answer, a tool call.
# The first start compiles and autotunes kernels: 20-40 min. Later starts reuse the caches.
# Usage: phases/30-serve.sh [start|stop|restart|status|test]
source "$(dirname "$0")/lib.sh"
CACHE="$HOME/.cache/pilot-llm"
cmd="${1:-start}"

ensure_key() {
  [ -s "$PILOT_HOME/api_key" ] || { umask 077; head -c 32 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 40 > "$PILOT_HOME/api_key"; }
  umask 077; printf 'VLLM_API_KEY=%s\n' "$(api_key)" > "$PILOT_HOME/vllm.env"
}

start() {
  docker image inspect "$VLLM_IMAGE" >/dev/null 2>&1 || fail "image missing: run phase 20"
  [ -f "$MODEL_DIR/config.json" ] || fail "model missing: run phase 10"
  ensure_key
  [ "$LLM_AUTH" = none ] && : > "$PILOT_HOME/vllm.env"
  mkdir -p "$CACHE"/{vllm,flashinfer,triton,b12x}
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  # The model's template accepts only xhigh|medium|low and answers HTTP 400 to "high", which
  # opencode, dsh and most OpenAI-compatible clients send. Map high and max to xhigh; nothing else changes.
  python3 - "$MODEL_DIR/chat_template.jinja" "$PILOT_HOME/chat_template.jinja" <<'PY' || fail "chat template patch failed"
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src).read()
anchor = "{%- set resolved_reasoning_effort = reasoning_effort|default('xhigh') %}"
if anchor not in t:
    sys.exit("anchor not found in " + src)
t = t.replace(anchor, anchor + "\n    {%- if resolved_reasoning_effort in ('high', 'max') %}{%- set resolved_reasoning_effort = 'xhigh' %}{%- endif %}", 1)
open(dst, "w").write(t)
PY
  # Flags: JDLondon7/qwen38-fp4-spark run 21 (measured on one GB10, 2026-10). Two of them are
  # what make it fit: expandable_segments stops the boot-time W4A16 repack from fragmenting
  # the allocator to ~1 GiB free, and --kv-cache-memory-bytes fixes the pool instead of
  # letting GPU_MEM fill the host. Thinking stays on; the agent decides per request.
  local spec="{\"method\":\"mtp\",\"num_speculative_tokens\":$MTP_TOKENS,\"draft_sample_method\":\"probabilistic\"}"
  docker run -d --pull never --name "$CONTAINER" --init --restart unless-stopped \
    --gpus all --ipc host --network host --shm-size=16g \
    --ulimit memlock=-1 --ulimit stack=67108864 \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
    --env-file "$PILOT_HOME/vllm.env" \
    -v "$MODEL_DIR:/model:ro" \
    -v "$PILOT_HOME/chat_template.jinja:/pilot/chat_template.jinja:ro" \
    -v "$CACHE/vllm:/root/.cache/vllm" -v "$CACHE/flashinfer:/root/.cache/flashinfer" \
    -v "$CACHE/triton:/root/.triton" -v "$CACHE/b12x:/root/.cache/b12x" \
    -e HF_HUB_OFFLINE=1 -e VLLM_PLE_TABLE_MEMORY=disk -e B12X_DISK_BACKEND=io_uring \
    -e CUTE_DSL_ARCH=sm_121a -e SAFETENSORS_FAST_GPU=1 -e VLLM_WORKER_MULTIPROC_METHOD=spawn \
    -e VLLM_SSM_CONV_STATE_LAYOUT=DS -e VLLM_USE_AOT_COMPILE=1 -e VLLM_USE_MEGA_AOT_ARTIFACT=1 \
    -e VLLM_USE_V2_MODEL_RUNNER=1 -e B12X_POLICY_MODE=auto -e VLLM_MXFP8_LM_HEAD=1 \
    -e VLLM_B12X_MOE_FP4_LAYER_MAX_INPUT_SCALE=w13 -e VLLM_B12X_MOE_FP4_FORCE_A16=1 \
    -e B12X_W4A16_A4_PREFILL=1 -e VLLM_ENGINE_READY_TIMEOUT_S=3600 \
    -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
    --entrypoint /usr/local/bin/vllm "$VLLM_IMAGE" \
    serve /model --host "$LLM_BIND" --port "$LLM_PORT" --served-model-name "$SERVED_NAME" \
    --tensor-parallel-size 1 --pipeline-parallel-size 1 \
    --mamba-cache-mode align --enable-prefix-caching --enable-chunked-prefill \
    --dtype bfloat16 --kv-cache-dtype fp8 --quantization modelopt_mixed \
    --block-size 16 --load-format b12x \
    --max-model-len "$MAX_MODEL_LEN" --max-num-seqs "$MAX_SEQS" --max-num-batched-tokens 4096 \
    --kv-cache-memory-bytes "$KV_BYTES" --gpu-memory-utilization "$GPU_MEM" \
    --mamba-ssm-cache-dtype bfloat16 --gdn-prefill-backend flashinfer --gdn-decode-kernel cuda \
    --speculative-config "$spec" \
    --linear-backend b12x --moe-backend b12x \
    --no-enable-flashinfer-autotune --mm-encoder-tp-mode data \
    --chat-template /pilot/chat_template.jinja --reasoning-parser qwen3 --tool-call-parser qwen3_xml --enable-auto-tool-choice \
    --compilation-config '{"pass_config":{"fuse_act_quant":true}}' >/dev/null
  if [ "$GUARD_GIB" != 0 ]; then
    setsid nohup "$(dirname "$0")/memguard.sh" "$CONTAINER" "$GUARD_GIB" >> "$PILOT_HOME/memguard.log" 2>&1 < /dev/null &
    log "memguard on: stops $CONTAINER below $GUARD_GIB GiB MemAvailable ($PILOT_HOME/memguard.log)"
  fi
  log "started $CONTAINER; waiting for /health (up to 60 min on the first start)"
  for i in $(seq 1 360); do
    curl -sf -m 5 "http://127.0.0.1:$LLM_PORT/health" >/dev/null && { ok "server healthy after $((i*10)) s"; return 0; }
    docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true || { docker logs --tail 40 "$CONTAINER"; tail -3 "$PILOT_HOME/memguard.log" 2>/dev/null; fail "container exited"; }
    sleep 10
  done
  docker logs --tail 40 "$CONTAINER"; fail "not healthy after 60 min"
}

test_server() {
  # The key stays in its file: Python reads it, so it is never on a command line (ps shows those).
  python3 - "http://127.0.0.1:$LLM_PORT/v1" "$KEY_FILE" "$SERVED_NAME" <<'PY'
import json, os, sys, time, urllib.request
u, keyfile, name = sys.argv[1:]
key = open(keyfile).read().strip() if os.path.exists(keyfile) else ""
hdr = {"Content-Type": "application/json", **({"Authorization": f"Bearer {key}"} if key else {})}
def call(path, body=None, timeout=600):
    r = urllib.request.Request(u + path, json.dumps(body).encode() if body else None, hdr)
    t = time.time(); d = json.load(urllib.request.urlopen(r, timeout=timeout)); return d, time.time() - t
def post(body):
    return call("/chat/completions", body)
ids = [m["id"] for m in call("/models", timeout=10)[0]["data"]]
if name not in ids:
    sys.exit(f"FAIL /v1/models lists {ids}, not {name}")
print(f"OK   /v1/models lists {name}")
d, s = post({"model": name, "max_tokens": 600, "chat_template_kwargs": {"enable_thinking": False},
             "messages": [{"role": "user", "content": "Write a haiku about a GPU. Then stop."}]})
print(f"OK   chat: {d['choices'][0]['message']['content'].strip()[:80]!r}")
# Decode speed: a long, predictable reply, so the prefill is a small part of the time.
d, s = post({"model": name, "max_tokens": 1500, "temperature": 0, "chat_template_kwargs": {"enable_thinking": False},
             "messages": [{"role": "user", "content": "Count from 1 to 300 in English words, comma separated. Nothing else."}]})
n = d["usage"]["completion_tokens"]
print(f"OK   decode: {n} tokens in {s:.1f} s = {n/s:.1f} tok/s (one stream, prefill included)")
tool = {"type": "function", "function": {"name": "get_tank_level", "description": "Level of a tank in percent",
        "parameters": {"type": "object", "properties": {"tank": {"type": "string"}}, "required": ["tank"]}}}
d, s = post({"model": name, "max_tokens": 4000, "tools": [tool],
             "messages": [{"role": "user", "content": "What is the level of tank T-101?"}]})
calls = d["choices"][0]["message"].get("tool_calls") or []
ok = calls and calls[0]["function"]["name"] == "get_tank_level" and "T-101" in calls[0]["function"]["arguments"]
print(("OK   " if ok else "FAIL ") + f"tool call: {calls[0]['function'] if calls else d['choices'][0]['message']}")
sys.exit(0 if ok else 1)
PY
}

case "$cmd" in
  start) start; test_server ;;
  restart) start; test_server ;;
  stop) docker rm -f "$CONTAINER" >/dev/null && ok "stopped" ;;
  status) docker ps --filter name="$CONTAINER" --format '{{.Names}} {{.Status}}'; curl -s -m 5 "http://127.0.0.1:$LLM_PORT/health" -o /dev/null -w 'health %{http_code}\n' ;;
  test) test_server ;;
  *) fail "usage: $0 start|stop|restart|status|test" ;;
esac
