#!/usr/bin/env bash
# Cursor Cloud Agent install step. Runs once per environment build, on the default
# branch, before the VM is snapshotted. Must stay idempotent and must exit.
# Self-contained on purpose: a dashboard-managed environment stores a verbatim copy.
set -euo pipefail

for d in "$(git rev-parse --show-toplevel 2>/dev/null || true)" /workspace /agent/repos/grafana; do
  if [ -n "$d" ] && [ -f "$d/pkg/cmd/grafana/main.go" ]; then cd "$d" && break; fi
done

# Go: the version go.mod pins, at /usr/local/go. /usr/local/bin precedes the distro's older go.
go_version="$(awk '/^go [0-9]/{print $2}' go.mod)"
if [ "$(/usr/local/go/bin/go env GOVERSION 2>/dev/null || true)" != "go$go_version" ]; then
  curl -fsSL "https://go.dev/dl/go$go_version.linux-$(dpkg --print-architecture).tar.gz" -o /tmp/go.tgz
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf /tmp/go.tgz
  rm -f /tmp/go.tgz
fi
sudo ln -sf /usr/local/go/bin/go /usr/local/go/bin/gofmt /usr/local/bin/

# The VM puts its own older node (/exec-daemon/node) ahead of nvm on PATH, and `nvm use`
# only swaps nvm's own entry, so the .nvmrc version's bin dir is prepended explicitly.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh" --no-use
node_version="$(cat .nvmrc)"
nvm which "$node_version" >/dev/null 2>&1 || nvm install "$node_version"
nvm alias default "$node_version" >/dev/null
node_dir="$NVM_DIR/versions/node/$node_version"
export PATH="$node_dir/bin:$PATH"

# Node 25+ no longer bundles corepack, so install the pnpm version package.json pins.
# Checked in the pinned Node's own bin dir: a pnpm elsewhere on PATH is not there on boot.
pnpm_version="$(node -p 'require("./package.json").packageManager.split("@")[1]')"
if [ "$("$node_dir/bin/pnpm" -v 2>/dev/null || true)" != "$pnpm_version" ]; then
  npm install -g --prefix "$node_dir" "pnpm@$pnpm_version"
fi

echo "node $(node -v), pnpm $(pnpm -v), $(go version)"

# Each step prints its duration into the build log.
TIMEFORMAT='[install] took %0lR'

time pnpm install --frozen-lockfile

time go mod download
# Exactly the build `make run` does (see .air.toml), so the boot-time build only recompiles
# what the checked-out branch changed. build-go rather than build-air: it leaves
# bin/grafana-air alone, which is busy while the server runs.
time make CGO_ENABLED=0 SOURCE_DATE_EPOCH=1767222000 GO_BUILD_DEV=1 build-go
# air, the hot-reload runner behind `make run`, is compiled on first use.
(cd .citools/src/air && time GOWORK=off go tool -n github.com/air-verse/air >/dev/null)
# go test compiles with default flags and shares no cache with the build above.
time go build ./pkg/...

# Development build into public/build. The backend needs boot.js from it at startup and
# serves the rest whenever the rspack dev server (pnpm start, port 3333) is not running.
time pnpm run dev
