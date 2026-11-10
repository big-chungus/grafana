#!/usr/bin/env bash
# Cursor Cloud Agent start step. Runs detached on every agent boot; output goes to
# /tmp/cursor/start-user/start-user.log. Safe to rerun: it only starts what is not running.
# Exits 0 once Grafana answers /api/health and the frontend dev server serves its manifest.
# Self-contained on purpose: a dashboard-managed environment stores a verbatim copy.
set -euo pipefail

for d in "$(git rev-parse --show-toplevel 2>/dev/null || true)" /workspace /agent/repos/grafana; do
  if [ -n "$d" ] && [ -f "$d/pkg/cmd/grafana/main.go" ]; then cd "$d" && break; fi
done

LOG_DIR=/tmp/grafana
mkdir -p "$LOG_DIR"

tmux_cmd=(tmux)
[ -f /exec-daemon/tmux.portal.conf ] && tmux_cmd=(tmux -f /exec-daemon/tmux.portal.conf)

# The VM puts its own older node ahead of nvm on PATH; sessions get the .nvmrc version first.
session_path="${NVM_DIR:-$HOME/.nvm}/versions/node/$(cat .nvmrc)/bin:$PATH"

start_session() {
  local session="$1" command="$2"
  if "${tmux_cmd[@]}" has-session -t "=$session" 2>/dev/null; then
    echo "$session: already running"
    return
  fi
  "${tmux_cmd[@]}" new-session -d -s "$session" -c "$PWD" -e "PATH=$session_path" \
    "$command 2>&1 | tee $LOG_DIR/$session.log"
  echo "$session: started '$command', log $LOG_DIR/$session.log"
}

wait_for() {
  local session="$1" url="$2" timeout="$3"
  until curl -sf -m 5 -o /dev/null "$url"; do
    if ! "${tmux_cmd[@]}" has-session -t "=$session" 2>/dev/null; then
      echo "$session: exited before $url was ready; see $LOG_DIR/$session.log" >&2
      return 1
    fi
    if [ "$SECONDS" -ge "$timeout" ]; then
      echo "$session: $url not ready after ${timeout}s; see $LOG_DIR/$session.log" >&2
      return 1
    fi
    sleep 1
  done
  echo "$session: $url ready after ${SECONDS}s"
}

SECONDS=0

# rspack dev server with hot module replacement. The backend points the browser at it, so
# the UI always reflects the working tree instead of the public/build baked into the snapshot.
start_session grafana-frontend "pnpm start"

# air starts the server in its own process group, so it can outlive a killed session and
# would then hold the port and the binary the next build has to replace.
if ! "${tmux_cmd[@]}" has-session -t "=grafana-backend" 2>/dev/null && pkill -x grafana-air; then
  timeout 30 bash -c 'while pgrep -x grafana-air >/dev/null; do sleep 0.5; done' || pkill -9 -x grafana-air || true
fi
# Rebuilds only what the checked-out branch changed, then again on every Go change.
start_session grafana-backend "make run"

wait_for grafana-backend http://localhost:3000/api/health 900
wait_for grafana-frontend http://localhost:3333/public/build/assets-manifest.json 900
