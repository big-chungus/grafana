# Cursor Cloud Agent environment

Scripts that prepare a Cursor Cloud Agent VM for Grafana development.

| File | Runs | Does |
| --- | --- | --- |
| `install.sh` | Once per environment build, on the default branch, before the snapshot | Pinned Node (`.nvmrc`) and pnpm (`packageManager`), `pnpm install --frozen-lockfile`, `go mod download`, `make build-go`, warms the `go test` compile cache, `pnpm run dev` into `public/build` |
| `start.sh` | On every agent boot, detached | Incremental `make build-go` for the checked-out branch, then `bin/grafana server` in tmux session `grafana-backend`, and waits for `/api/health` |
| `node-env.sh` | Sourced by hand | Puts the pinned Node and pnpm first on `PATH` |
| `environment.json` | Read by Cursor when the environment records this file | Points `install` and `start` at the scripts above |

The environment is currently dashboard-managed, so the dashboard holds a verbatim copy of
`install.sh` and `start.sh`. When you change a script, rebuild and re-save the environment
too, or switch it to read `.cursor/environment.json`.

## Using it

Grafana is at <http://localhost:3000> (sign in as `admin` / `admin`) once boot finishes. Boot
output is in `/tmp/cursor/start-user/start-user.log`, and server logs are in `/tmp/grafana/backend.log`.
The UI is the `public/build` from the snapshot, built from the default branch.

The VM puts an older `node` first on `PATH`, so start every frontend shell with
`source .cursor/node-env.sh`.

```bash
# Backend
make build-go                                   # incremental; stop the server first, or the copy to bin/grafana fails
go test ./pkg/services/folder/folderimpl/       # targeted Go tests
tmux kill-session -t grafana-backend && bash .cursor/start.sh   # restart the server after backend changes

# Frontend
source .cursor/node-env.sh
pnpm exec jest --no-watch public/app/core/utils/  # targeted unit tests (never the default --watch)
pnpm run dev                                    # rebuild public/build (about 40s)
pnpm start                                      # rspack dev server on :3333 with HMR, run it in tmux; the backend picks it up automatically
```

If a branch changes `pnpm-lock.yaml` or `go.mod`, run `pnpm install --frozen-lockfile` or
`go mod download` yourself. The snapshot reflects the default branch only.
