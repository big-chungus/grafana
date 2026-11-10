#!/usr/bin/env bash
# Cursor Cloud Agent install step. Runs once per environment build, on the default
# branch, before the VM is snapshotted. Must stay idempotent and must exit.
# Self-contained on purpose: a dashboard-managed environment stores a verbatim copy.
set -euo pipefail

for d in "$(git rev-parse --show-toplevel 2>/dev/null || true)" /workspace /agent/repos/grafana; do
  if [ -n "$d" ] && [ -f "$d/pkg/cmd/grafana/main.go" ]; then cd "$d" && break; fi
done

# The VM puts its own older node (/exec-daemon/node) ahead of nvm on PATH, and `nvm use`
# only swaps nvm's own entry, so the .nvmrc version's bin dir is prepended explicitly.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
node_version="$(cat .nvmrc)"
nvm which "$node_version" >/dev/null 2>&1 || nvm install "$node_version"
nvm alias default "$node_version" >/dev/null
export PATH="$NVM_DIR/versions/node/$node_version/bin:$PATH"

# Node 25+ no longer bundles corepack, so install the pnpm version package.json pins.
pnpm_version="$(node -p 'require("./package.json").packageManager.split("@")[1]')"
if [ "$(pnpm -v 2>/dev/null || true)" != "$pnpm_version" ]; then
  npm install -g --prefix "$NVM_DIR/versions/node/$node_version" "pnpm@$pnpm_version"
fi

echo "node $(node -v), pnpm $(pnpm -v), $(go version)"

pnpm install --frozen-lockfile

go mod download
make build-go
# make build-go uses -trimpath, which go test does not, so they share no compile cache.
# This warms the cache go test reuses for every package the server imports.
go build -o /dev/null ./pkg/cmd/grafana

# Development build into public/build. The backend serves it whenever the rspack dev
# server (pnpm start, port 3333) is not running, so the UI works right after boot.
pnpm run dev
