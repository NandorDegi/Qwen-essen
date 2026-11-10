#!/usr/bin/env bash
# Downloads the checkpoint (96 GiB). Resumable: run again after any interruption.
# Run detached: setsid nohup phases/10-model.sh > ~/pilot-logs/10-model.log 2>&1 < /dev/null &
source "$(dirname "$0")/lib.sh"
if ! hf version >/dev/null 2>&1; then
  command -v uv >/dev/null || retry 5 sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
  export PATH="$HOME/.local/bin:$PATH"
  retry 5 uv tool install --force huggingface_hub
  hash -r
fi
hf version >/dev/null 2>&1 || fail "hf does not run"
HFPY="$(uv tool dir 2>/dev/null)/huggingface-hub/bin/python"; [ -x "$HFPY" ] || HFPY=python3
mkdir -p "$MODEL_DIR"
retry 20 hf download "$MODEL_REPO" --revision "$MODEL_REVISION" --local-dir "$MODEL_DIR" || fail "download did not finish; run the phase again"
# Verify every file against the hub listing (size), so a truncated shard is caught here.
"$HFPY" - "$MODEL_REPO" "$MODEL_REVISION" "$MODEL_DIR" <<'PY'
import os, sys
from huggingface_hub import HfApi
repo, rev, d = sys.argv[1:]
bad = []
for s in HfApi().model_info(repo, revision=rev, files_metadata=True).siblings:
    p = os.path.join(d, s.rfilename)
    if not os.path.exists(p) or (s.size and os.path.getsize(p) != s.size):
        bad.append(s.rfilename)
print("all files present and sized" if not bad else f"BAD: {bad}")
sys.exit(1 if bad else 0)
PY
ok "model in $MODEL_DIR ($(du -shL "$MODEL_DIR" | cut -f1))"
