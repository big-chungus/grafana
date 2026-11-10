#!/usr/bin/env bash
# Cursor Cloud Agent start step. Runs detached on every agent boot; output goes to
# /tmp/cursor/start-user/start-user.log. Exits 0 once Grafana answers /api/health.
# Self-contained on purpose: a dashboard-managed environment stores a verbatim copy.
set -euo pipefail

for d in "$(git rev-parse --show-toplevel 2>/dev/null || true)" /workspace /agent/repos/grafana; do
  if [ -n "$d" ] && [ -f "$d/pkg/cmd/grafana/main.go" ]; then cd "$d" && break; fi
done

LOG_DIR=/tmp/grafana
SESSION=grafana-backend
mkdir -p "$LOG_DIR"

tmux_cmd=(tmux)
[ -f /exec-daemon/tmux.portal.conf ] && tmux_cmd=(tmux -f /exec-daemon/tmux.portal.conf)

if curl -sf -o /dev/null http://localhost:3000/api/health; then
  echo "Grafana is already running on :3000"
  exit 0
fi
"${tmux_cmd[@]}" kill-session -t "=$SESSION" 2>/dev/null || true

# The snapshot was built from the default branch; this recompiles only what the checked-out
# branch changed.
SECONDS=0
make build-go
echo "backend build: ${SECONDS}s"

if [ ! -f public/build/assets-manifest.json ]; then
  echo "public/build is missing: the UI needs 'pnpm run dev' or 'pnpm start' (see .cursor/README.md)" >&2
fi

SECONDS=0
"${tmux_cmd[@]}" new-session -d -s "$SESSION" -c "$PWD" \
  "./bin/grafana server -homepath . -packaging=dev cfg:app_mode=development 2>&1 | tee $LOG_DIR/backend.log"

for _ in $(seq 1 300); do
  if curl -sf -o /dev/null http://localhost:3000/api/health; then
    echo "Grafana ready on http://localhost:3000 after ${SECONDS}s (tmux session: $SESSION)"
    exit 0
  fi
  sleep 1
done
echo "Grafana did not become healthy in 300s; see $LOG_DIR/backend.log" >&2
exit 1
