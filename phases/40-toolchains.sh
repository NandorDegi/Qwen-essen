#!/usr/bin/env bash
# Installs the agent's toolchains in user space (~/.local, ~/.cargo, ~/go), no sudo:
# Node + TypeScript LSP, Python (uv + pyright), Go + gopls, Rust + rust-analyzer,
# opencode, and Chromium for the Playwright MCP server.
source "$(dirname "$0")/lib.sh"
OPT="$HOME/.local/opt"; mkdir -p "$OPT" "$HOME/.local/bin"

# One env file for every shell and for opencode's child processes.
cat > "$PILOT_HOME/env.sh" <<ENV
export PATH="\$HOME/.local/opt/node/bin:\$HOME/.local/opt/go/bin:\$HOME/go/bin:\$HOME/.cargo/bin:\$HOME/.local/bin:\$PATH"
export NPM_CONFIG_PREFIX="\$HOME/.local"
if [ -s "\$HOME/.config/pilot/api_key" ]; then export PILOT_LLM_KEY="\$(cat "\$HOME/.config/pilot/api_key")"; fi
true
ENV
chmod 600 "$PILOT_HOME/env.sh"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$rc" ] || continue
  grep -q 'pilot/env.sh' "$rc" || printf '\n[ -f "$HOME/.config/pilot/env.sh" ] && . "$HOME/.config/pilot/env.sh"\n' >> "$rc"
done
source "$PILOT_HOME/env.sh"

fetch() { retry 8 curl -fsSL --retry 3 -C - -o "$2" "$1"; }

# Node
if ! node --version 2>/dev/null | grep -q "$NODE_VERSION"; then
  f="node-$NODE_VERSION-linux-arm64.tar.xz"; fetch "https://nodejs.org/dist/$NODE_VERSION/$f" "/tmp/$f"
  rm -rf "$OPT/node-$NODE_VERSION-linux-arm64"; tar -xJf "/tmp/$f" -C "$OPT"; ln -sfn "$OPT/node-$NODE_VERSION-linux-arm64" "$OPT/node"
fi
ok "node $(node --version)"

# Go
if ! go version 2>/dev/null | grep -q "$GO_VERSION "; then
  f="$GO_VERSION.linux-arm64.tar.gz"; fetch "https://go.dev/dl/$f" "/tmp/$f"
  rm -rf "$OPT/go"; tar -xzf "/tmp/$f" -C "$OPT"
fi
ok "$(go version)"
command -v gopls >/dev/null || retry 5 go install golang.org/x/tools/gopls@latest
ok "gopls $(gopls version | head -1)"

# Rust
if ! command -v rustup >/dev/null; then
  fetch https://sh.rustup.rs /tmp/rustup.sh; sh /tmp/rustup.sh -y --no-modify-path --profile minimal
fi
retry 5 rustup toolchain install stable --component rust-analyzer,clippy,rustfmt >/dev/null
ok "$(rustc --version); rust-analyzer $(rust-analyzer --version | cut -d' ' -f2)"

# Python
command -v uv >/dev/null || { fetch https://astral.sh/uv/install.sh /tmp/uv.sh; sh /tmp/uv.sh; }
ok "uv $(uv --version | cut -d' ' -f2), python $(python3 --version | cut -d' ' -f2)"

# npm packages: opencode, TypeScript LSP, pyright
retry 5 npm install -g --no-fund --no-audit "opencode-ai@$OPENCODE_VERSION" \
  "typescript@$TYPESCRIPT_VERSION" "typescript-language-server@$TSLS_VERSION" "pyright@$PYRIGHT_VERSION" \
  "@playwright/mcp@$PLAYWRIGHT_MCP_VERSION" >/dev/null
ok "opencode $(opencode --version), tsls $(typescript-language-server --version), pyright $(pyright --version | cut -d' ' -f2)"

# Chromium for the Playwright MCP server (the browser revision its playwright pins).
pw="$(dirname "$(readlink -f "$(command -v mcp-server-playwright)")")"
retry 5 node "$pw/../playwright-core/cli.js" install chromium >/dev/null 2>&1 || retry 5 npx -y playwright install chromium
missing=$(find "$HOME/.cache/ms-playwright" -name chrome -type f -path '*chrome-linux*' -exec ldd {} \; 2>/dev/null | grep 'not found' | sort -u || true)
[ -z "$missing" ] && ok "chromium libraries complete" || log "WARN chromium needs system libraries (one sudo step): sudo npx playwright install-deps chromium -- missing: $missing"
ok "toolchains done; open a new shell or: source ~/.config/pilot/env.sh"
