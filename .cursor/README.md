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

Grafana is at <http://localhost:3000> (sign in as `admin` / `admin`) within a minute of the VM
coming up. The first sign-in asks for a new password: choose Skip.

On three fresh boots of the environment build `start.sh` took 48 s, 55 s and 65 s, and the
first page load then took under 2 s. Of that, 38 s to 51 s was the backend relinking, because
the Makefile links the commit and branch name into the binary. `start.sh` has since stopped
that: it passes the commit and branch the baked binary was linked with, so a branch that
changes no Go code skips the link. On a VM that had been up for a while this cut the build
step from 11 s to 2 s and the whole script from 30 s to 16 s. It has not been timed on a fresh
boot yet.

The price is that **the backend reports the environment build's commit and branch**, in
`/api/health` and in the page footer, whatever you have checked out. `git rev-parse HEAD` is
the truth. The code that runs is always your working tree.

`start` runs on boot only when the environment's saved configuration contains it; a draft build
or an unsaved proposal does not. If `/tmp/cursor/start-user/` is missing, it did not run, so run
`bash -l .cursor/start.sh` yourself. The timings above come from running it that way: the
automatic run on boot had not been observed when this was written.

Both servers are already running after `start`, so do not start second copies:

| tmux session | Command | Log | Reloads on |
| --- | --- | --- | --- |
| `grafana-backend` | `make run` (air) | `/tmp/grafana/grafana-backend.log` | Go, `conf/` and `public/views` changes: rebuilds and restarts the server |
| `grafana-frontend` | `pnpm start` (rspack dev server on `:3333`) | `/tmp/grafana/grafana-frontend.log` | Frontend changes: recompiles in 2 to 6 s and hot-swaps into the open page |

The UI is served from the working tree, not from the `public/build` baked into the snapshot. A
changed component shows up in the open page without a reload. A value read once at module
load, such as a static class field, only shows after a reload, so reload the page before you
take a screenshot.

For about 20 s after its first start on a VM, the backend downloads its data source plugins
into `data/plugins` and the dev server recompiles a few times. Both settle on their own.

Boot output is in `/tmp/cursor/start-user/start-user.log`, with the exit code in
`start-user.status` next to it. Rerun `bash .cursor/start.sh` to bring back a session you
stopped; it leaves running ones alone.

The VM puts an older `node` first on `PATH`, so start every frontend shell with
`source .cursor/node-env.sh`.

```bash
# Backend
go test ./pkg/services/folder/folderimpl/       # targeted Go tests; the first run of a large package links for up to 30 s
go build ./pkg/...                              # compile check against the baked cache
make build-backend                              # release-flag build into bin/grafana, a full compile of over 2 min:
                                                # the snapshot caches the dev build the running server (bin/grafana-air) uses
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
