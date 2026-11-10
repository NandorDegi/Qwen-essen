#!/usr/bin/env bash
# Pulls the pinned vLLM image (~25 GB). Docker resumes layers that finished.
source "$(dirname "$0")/lib.sh"
docker image inspect "$VLLM_IMAGE" >/dev/null 2>&1 || retry 10 docker pull "$VLLM_IMAGE" || fail "pull failed; run again"
ok "image $VLLM_IMAGE"
