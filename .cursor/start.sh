#!/usr/bin/env bash
# Cursor Cloud Agent start step. Runs detached on agent boot when the environment's saved
# configuration contains it; output then goes to /tmp/cursor/start-user/start-user.log.
# Safe to rerun: it only starts what is not running. Exits 0 once the login page loads.
# Self-contained on purpose: a dashboard-managed environment stores a verbatim copy.
set -euo pipefail

for d in "$(git rev-parse --show-toplevel 2>/dev/null || true)" /agent/repos/grafana /workspace; do
  if [ -n "$d" ] && [ -f "$d/pkg/cmd/grafana/main.go" ]; then cd "$d" && break; fi
done

LOG_DIR=/tmp/grafana
mkdir -p "$LOG_DIR"

tmux_cmd=(tmux)
[ -f /exec-daemon/tmux.portal.conf ] && tmux_cmd=(tmux -f /exec-daemon/tmux.portal.conf)

# The VM puts its own older node ahead of nvm on PATH. Exported rather than passed with
# `new-session -e`: tmux gives a new pane the PATH of the client that creates it.
export PATH="${NVM_DIR:-$HOME/.nvm}/versions/node/$(cat .nvmrc)/bin:$PATH"

start_session() {
  local session="$1" command="$2"
  if "${tmux_cmd[@]}" has-session -t "=$session" 2>/dev/null; then
    echo "$session: already running"
    return
  fi
  "${tmux_cmd[@]}" new-session -d -s "$session" -c "$PWD" \
    "$command 2>&1 | tee $LOG_DIR/$session.log"
  echo "$session: started '$command', log $LOG_DIR/$session.log"
}

declare -A ready_url=(
  [grafana-backend]=http://localhost:3000/api/health
  [grafana-frontend]=http://localhost:3333/public/build/assets-manifest.json
)

# Polls every session in each pass, so each "ready after" time is that session's own.
wait_for_all() {
  local timeout="$1" session url
  local -a pending=("${!ready_url[@]}") waiting
  while [ "${#pending[@]}" -gt 0 ]; do
    waiting=()
    for session in "${pending[@]}"; do
      url="${ready_url[$session]}"
      if curl -sf -m 5 -o /dev/null "$url"; then
        echo "$session: $url ready after ${SECONDS}s"
      elif ! "${tmux_cmd[@]}" has-session -t "=$session" 2>/dev/null; then
        echo "$session: exited before $url was ready; see $LOG_DIR/$session.log" >&2
        return 1
      elif [ "$SECONDS" -ge "$timeout" ]; then
        echo "$session: $url not ready after ${timeout}s; see $LOG_DIR/$session.log" >&2
        return 1
      else
        waiting+=("$session")
      fi
    done
    pending=("${waiting[@]}")
    [ "${#pending[@]}" -eq 0 ] || sleep 1
  done
}

# Both servers answer before a page can load: the backend's first start on a VM sets off
# another full rspack compile, and the dev server holds every request until it is done. A held
# request is not a failure, so one attempt is allowed to outlast that compile.
wait_for_page() {
  local url="$1" timeout="$2" session
  until curl -sf -m 60 -o /dev/null "$url"; do
    for session in "${!ready_url[@]}"; do
      if ! "${tmux_cmd[@]}" has-session -t "=$session" 2>/dev/null; then
        echo "$session: exited before $url loaded; see $LOG_DIR/$session.log" >&2
        return 1
      fi
    done
    if [ "$SECONDS" -ge "$timeout" ]; then
      echo "page: $url did not load after ${timeout}s; see the logs in $LOG_DIR" >&2
      return 1
    fi
    sleep 1
  done
  echo "page: $url loaded after ${SECONDS}s"
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
# The Makefile links the commit and branch into the binary, so every new checkout would relink
# it even when no Go code changed. Passing the values the existing binary was linked with lets
# Go skip that link. The server then reports that commit and branch, not the checkout's.
link_flags="$(go version -m "bin/$(go env GOOS)/$(go env GOARCH)/grafana" 2>/dev/null || true)"
built_commit="$(sed -n 's/.*-X main\.commit=\([0-9a-f]\{40\}\) .*/\1/p' <<<"$link_flags")"
built_branch="$(sed -n 's|.*-X main\.buildBranch=\([A-Za-z0-9._/-]\{1,\}\) .*|\1|p' <<<"$link_flags")"
backend_command="make run"
if [ -n "$built_commit" ] && [ -n "$built_branch" ]; then
  backend_command="COMMIT_SHA=$built_commit BUILD_BRANCH=$built_branch make run"
fi
# Rebuilds only what the checked-out branch changed, then again on every Go change.
start_session grafana-backend "$backend_command"

wait_for_all 900
wait_for_page http://localhost:3000/login 900
