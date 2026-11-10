# Cursor Cloud Agent environment

Scripts that prepare a Cursor Cloud Agent VM for Grafana development.

| File | Runs | Does |
| --- | --- | --- |
| `install.sh` | Once per environment build, on the default branch, before the snapshot | Pinned Go (`go.mod`) into `/usr/local/go`, pinned Node (`.nvmrc`) and pnpm (`packageManager`), `pnpm install --frozen-lockfile`, `go mod download`, the same backend build `make run` does, a warm `go test` compile cache, `pnpm run dev` into `public/build` |
| `start.sh` | On every agent boot, detached, once the environment's saved configuration contains it; by hand before that | `make run` in tmux session `grafana-backend` and `pnpm start` in tmux session `grafana-frontend`, then waits until the login page loads |
| `node-env.sh` | Sourced by hand | Puts the pinned Node and pnpm first on `PATH` |
| `environment.json` | Read by Cursor when the environment records this file | Points `install` and `start` at the scripts above |

The environment is dashboard-managed. The dashboard does not read these files: it runs the
copy of `install.sh` and `start.sh` that was last saved there, and until a configuration with
both scripts has been saved it runs neither. When you change a script, rebuild and re-save the
environment too, or switch it to read `.cursor/environment.json`.

## Using it

Grafana runs at <http://localhost:3000>. Sign in as `admin` / `admin`; the first sign-in asks
for a new password: choose Skip.

Check whether it is up before you start anything:

```bash
curl -sf -m 60 -o /dev/null http://localhost:3000/login && echo up
```

If nothing answers, run `bash -l .cursor/start.sh`. It starts whichever of the two sessions is
missing, leaves running ones alone, and exits 0 once the login page loads. If a start from
boot is still under way, it waits for that one.

`start` runs on boot only when the environment's saved configuration contains it; a draft build
or an unsaved proposal does not. That automatic run had not been observed when this was
written: every fresh boot so far came from a configuration without it, and the script was run
by hand. When it has run, its output is in `/tmp/cursor/start-user/start-user.log`, with the
exit code in `start-user.status` next to it.

Measured on two fresh boots of the environment build, on a branch with no Go changes:

| After launching `start.sh` | Boot 1 | Boot 2 |
| --- | --- | --- |
| Both servers answer | 29 s | 33 s |
| Login page loads | 38 s | 42 s |

The page comes later because the backend's first start on a VM sets off a second rspack
compile of 8 to 10 s, and the dev server holds every request until it is done. On those boots
the script still returned when the servers answered. It now waits for the page, which was only
run on a VM that had been up for a while (36 s, the page 5 s after the servers), so expect
about 40 s on a fresh boot.

Of that time, 15 s to 19 s is a `go build` that compiles nothing: the VM's disk is still being
loaded, and the same step takes 2 s on a warm VM. Before `start.sh` skipped the relink
described next, three fresh boots took 48 s, 55 s and 65 s.

The Makefile links the commit and branch name into the binary, so every new checkout would
relink it, 38 s to 51 s on a fresh boot. `start.sh` passes the values the baked binary was
linked with instead, so a branch that changes no Go code skips the link. The price is that
**`/api/health` and the page footer show the environment build's commit, not your
checkout's.** The branch name, which appears only in `/metrics` (`grafana_build_info`) and the
startup log, is the build's too. `git rev-parse HEAD` is the truth. The code that runs is
always your working tree.

Once started, both servers keep running, so do not start second copies:

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

The VM puts an older `node` first on `PATH`, so start every frontend shell with
`source .cursor/node-env.sh`.

```bash
# Backend
go test ./pkg/services/folder/folderimpl/       # targeted Go tests; the first run of a large package links for up to 30 s
go build ./pkg/...                              # compile check against the baked cache
make build-backend                              # release-flag build into bin/grafana, a full compile of over 2 min:
                                                # the snapshot caches the dev build the running server (bin/grafana-air) uses
tmux kill-session -t grafana-backend; bash -l .cursor/start.sh   # force a clean server restart

# Frontend
source .cursor/node-env.sh
pnpm exec jest --no-watch public/app/core/utils/  # targeted unit tests (never the default --watch)
pnpm run dev                                    # rebuild public/build, only used while grafana-frontend is stopped
```

The dev server holds about 5 GB of memory. To free it, `tmux kill-session -t grafana-frontend`:
Grafana then serves `public/build`, which was built from the default branch, so run
`pnpm run dev` if your branch changes the frontend.

If a branch changes `pnpm-lock.yaml`, `go.mod`, `.nvmrc` or the Go version, run
`bash .cursor/install.sh` yourself. The snapshot reflects the default branch only.
