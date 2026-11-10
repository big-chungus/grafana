# Cursor Cloud Agent environment

Scripts that prepare a Cursor Cloud Agent VM for Grafana development.

| File | Runs | Does |
| --- | --- | --- |
| `install.sh` | Once per environment build, on the default branch, before the snapshot | Pinned Go (`go.mod`) into `/usr/local/go`, pinned Node (`.nvmrc`) and pnpm (`packageManager`), `pnpm install --frozen-lockfile`, `go mod download`, the same backend build `make run` does, a warm `go test` compile cache, `pnpm run dev` into `public/build` |
| `start.sh` | On every agent boot, detached | `make run` in tmux session `grafana-backend` and `pnpm start` in tmux session `grafana-frontend`, then waits for both to answer |
| `node-env.sh` | Sourced by hand | Puts the pinned Node and pnpm first on `PATH` |
| `environment.json` | Read by Cursor when the environment records this file | Points `install` and `start` at the scripts above |

The environment is currently dashboard-managed, so the dashboard holds a verbatim copy of
`install.sh` and `start.sh`. When you change a script, rebuild and re-save the environment
too, or switch it to read `.cursor/environment.json`.

## Using it

Grafana is at <http://localhost:3000> (sign in as `admin` / `admin`) once boot finishes, about
30 seconds after the VM is up. Both servers are already running, so do not start second copies:

| tmux session | Command | Log | Reloads on |
| --- | --- | --- | --- |
| `grafana-backend` | `make run` (air) | `/tmp/grafana/grafana-backend.log` | Go, `conf/` and `public/views` changes: rebuilds and restarts the server |
| `grafana-frontend` | `pnpm start` (rspack dev server on `:3333`) | `/tmp/grafana/grafana-frontend.log` | Frontend changes: hot module replacement in the open page |

Boot output is in `/tmp/cursor/start-user/start-user.log`, with the exit code in
`start-user.status` next to it. Rerun `bash .cursor/start.sh` to bring back a session you
stopped; it leaves running ones alone.

The VM puts an older `node` first on `PATH`, so start every frontend shell with
`source .cursor/node-env.sh`.

```bash
# Backend
go test ./pkg/services/folder/folderimpl/       # targeted Go tests
make build-backend                              # release-flag build into bin/grafana; the running server is bin/grafana-air
tmux kill-session -t grafana-backend; bash .cursor/start.sh   # force a clean server restart

# Frontend
source .cursor/node-env.sh
pnpm exec jest --no-watch public/app/core/utils/  # targeted unit tests (never the default --watch)
pnpm run dev                                    # rebuild public/build, only used while grafana-frontend is stopped
```

The dev server holds about 4.5 GB of memory. To free it, `tmux kill-session -t grafana-frontend`:
Grafana then serves `public/build`, which was built from the default branch, so run
`pnpm run dev` if your branch changes the frontend.

If a branch changes `pnpm-lock.yaml`, `go.mod`, `.nvmrc` or the Go version, run
`bash .cursor/install.sh` yourself. The snapshot reflects the default branch only.
