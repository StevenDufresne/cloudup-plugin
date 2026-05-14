#!/usr/bin/env bash
# Cloudup MCP wrapper — resolves the wallet key from macOS Keychain (with an
# env-var fallback for back-compat), then execs mpp-remote with the key
# exported as MPP_WALLET_PRIVATE_KEY.
#
# Key resolution order:
#   1. $CLOUDUP_WALLET_KEY (env var) — back-compat with older setups
#   2. macOS Keychain item: service=cloudup, account=wallet
#
# npx resolution: Claude Code's MCP launch environment does NOT inherit
# nvm/Homebrew PATH adjustments (this is why an earlier wrapper attempt was
# dropped in 0.1.3 — see commit 3f86299). We re-introduce the wrapper here
# because Keychain access can't live in .mcp.json substitution, so we have
# to make npx-finding robust ourselves.

set -euo pipefail

# ---- npx discovery -------------------------------------------------------

find_npx() {
    command -v npx >/dev/null 2>&1 && return 0

    # Sourcing user shell init files non-interactively to pick up nvm/PATH.
    if [ -s "$HOME/.zshenv" ]; then
        # shellcheck disable=SC1091
        . "$HOME/.zshenv" 2>/dev/null || true
        command -v npx >/dev/null 2>&1 && return 0
    fi

    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
    if [ -s "$nvm_dir/nvm.sh" ]; then
        export NVM_DIR="$nvm_dir"
        # shellcheck disable=SC1091
        . "$NVM_DIR/nvm.sh" 2>/dev/null || true
        command -v npx >/dev/null 2>&1 && return 0
    fi

    # Probe common install locations. Globs that don't match are left literal
    # by `set -f` defaults; we handle that with the -x test.
    local cand
    for cand in \
        /opt/homebrew/bin/npx \
        /usr/local/bin/npx \
        "$HOME"/.nvm/versions/node/*/bin/npx \
        "$HOME"/.volta/bin/npx \
        /usr/bin/npx; do
        if [ -x "$cand" ]; then
            export PATH="$(dirname "$cand"):$PATH"
            return 0
        fi
    done

    return 1
}

if ! find_npx; then
    cat >&2 <<'EOF'
cloudup: cannot find `npx` on PATH.

Claude Code launches MCP servers without sourcing your shell rc, so nvm /
Homebrew PATH additions are not inherited. Install Node.js system-wide
(e.g. via Homebrew: `brew install node`) or add the directory containing
`npx` to a non-interactive shell init file like ~/.zshenv.
EOF
    exit 1
fi

# ---- wallet key resolution ----------------------------------------------

KEY="${CLOUDUP_WALLET_KEY:-}"

if [ -z "$KEY" ] && command -v security >/dev/null 2>&1; then
    KEY="$(security find-generic-password -s cloudup -a wallet -w 2>/dev/null || true)"
fi

if [ -z "$KEY" ]; then
    cat >&2 <<'EOF'
cloudup: no wallet key configured.

Run /cloudup-setup in Claude Code to provision a key into macOS Keychain,
or set CLOUDUP_WALLET_KEY in your environment.
EOF
    exit 1
fi

# ---- exec mpp-remote -----------------------------------------------------

export MPP_WALLET_PRIVATE_KEY="$KEY"
export MPP_MAX_AMOUNT_USD="${CLOUDUP_MAX_USD:-0.10}"

# Cloudup staging is IP-restricted to the A8c network, so we route upstream
# traffic through the conventional A8c SOCKS5 forwarder on localhost:8080
# (typically `ssh -D 8080 <bastion>`).
exec npx -y github:tellyworth/mpp-remote \
    --proxy socks5h://127.0.0.1:8080 \
    "${CLOUDUP_MCP_URL:-https://api.stage-cloudup.com/mcp/public}"
