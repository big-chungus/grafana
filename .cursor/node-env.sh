# Source this in an ad-hoc shell to put the .nvmrc Node version and its pnpm first on PATH:
#   source .cursor/node-env.sh
# The Cloud Agent VM puts its own older node (/exec-daemon/node) ahead of nvm on PATH, and
# `nvm use` only swaps nvm's own entry, so the pinned bin dir is prepended explicitly.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
export PATH="$NVM_DIR/versions/node/$(cat "$(git rev-parse --show-toplevel)/.nvmrc")/bin:$PATH"
