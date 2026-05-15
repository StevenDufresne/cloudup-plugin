#!/usr/bin/env bash
# Cloudup MCP wrapper — picks a signer for mpp-remote and execs the bridge.
#
# Two modes, picked by which env var is set:
#
#   1. Default (dev machines): resolve the user's Privy agent-wallet address
#      via the `paw` CLI (@privy-io/agent-wallet-cli) and pass it to
#      mpp-remote as PRIVY_WALLET_ADDRESS. The signing key never leaves Privy.
#      One-time prereq, run by `/cloudup-setup`:
#          npm i -g @privy-io/agent-wallet-cli
#          paw login
#
#   2. CI / headless: if CLOUDUP_WALLET_KEY is set (typically a TeamCity
#      secret), skip paw discovery and pass it through as
#      MPP_WALLET_PRIVATE_KEY. mpp-remote signs locally with viem. Suitable
#      for unattended use where `paw login` (browser-based, host-bound
#      session) can't run.
#
# Claude Code's MCP launch environment does NOT inherit nvm/Homebrew PATH
# adjustments, so we have to find `npx` (and `paw`, in mode 1) ourselves.

set -euo pipefail

# ---- bin discovery -------------------------------------------------------

find_bin() {
    local name="$1" p

    p="$(command -v "$name" 2>/dev/null || true)"
    if [ -n "$p" ]; then echo "$p"; return 0; fi

    if [ -s "$HOME/.zshenv" ]; then
        # shellcheck disable=SC1091
        . "$HOME/.zshenv" 2>/dev/null || true
    fi
    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
    if [ -s "$nvm_dir/nvm.sh" ]; then
        export NVM_DIR="$nvm_dir"
        # shellcheck disable=SC1091
        . "$NVM_DIR/nvm.sh" 2>/dev/null || true
    fi

    p="$(command -v "$name" 2>/dev/null || true)"
    if [ -n "$p" ]; then echo "$p"; return 0; fi

    local cand
    for cand in \
        /opt/homebrew/bin/"$name" \
        /usr/local/bin/"$name" \
        "$HOME"/.nvm/versions/node/*/bin/"$name" \
        "$HOME"/.volta/bin/"$name" \
        /usr/bin/"$name"; do
        if [ -x "$cand" ]; then echo "$cand"; return 0; fi
    done

    return 1
}

NPX="$(find_bin npx)" || {
    cat >&2 <<'EOF'
cloudup: cannot find `npx` on PATH.

Claude Code launches MCP servers without sourcing your shell rc, so nvm /
Homebrew PATH additions are not inherited. Install Node.js system-wide
(e.g. via Homebrew: `brew install node`) or add the directory containing
`npx` to a non-interactive shell init file like ~/.zshenv.
EOF
    exit 1
}

export PATH="$(dirname "$NPX"):$PATH"

# ---- signer selection ----------------------------------------------------

if [ -n "${CLOUDUP_WALLET_KEY:-}" ]; then
    # Mode 2: local-key signer (CI / headless).
    export MPP_WALLET_PRIVATE_KEY="$CLOUDUP_WALLET_KEY"
else
    # Mode 1: Privy agent-wallet CLI (dev machines).
    PAW="$(find_bin paw)" || {
        cat >&2 <<'EOF'
cloudup: cannot find `paw` (@privy-io/agent-wallet-cli).

Either install paw and log in:

    npm i -g @privy-io/agent-wallet-cli
    paw login

…or set CLOUDUP_WALLET_KEY to a 0x-prefixed private key for headless /
CI use. See the plugin README for the trade-offs.
EOF
        exit 1
    }
    export PATH="$(dirname "$PAW"):$PATH"

    if ! WALLETS_OUT="$("$PAW" list-wallets 2>&1)"; then
        cat >&2 <<EOF
cloudup: \`paw list-wallets\` failed. Run \`paw login\` first.

$WALLETS_OUT
EOF
        exit 1
    fi

    # `paw list-wallets` prints a human-readable block; pull the Ethereum line.
    ADDR="$(printf '%s\n' "$WALLETS_OUT" | sed -nE 's/.*Ethereum:[[:space:]]+(0x[0-9a-fA-F]+).*/\1/p' | head -n1)"

    if [ -z "$ADDR" ]; then
        cat >&2 <<EOF
cloudup: could not parse an Ethereum address from \`paw list-wallets\`:

$WALLETS_OUT
EOF
        exit 1
    fi

    export PRIVY_WALLET_ADDRESS="$ADDR"
    export PRIVY_AGENT_WALLET_BIN="$PAW"
fi

# ---- exec mpp-remote -----------------------------------------------------

export MPP_MAX_AMOUNT_USD="${CLOUDUP_MAX_USD:-0.20}"

# Cloudup staging is IP-restricted to the A8c network, so we route upstream
# traffic through the conventional A8c SOCKS5 forwarder on localhost:8080
# (typically `ssh -D 8080 <bastion>`).
exec "$NPX" -y github:tellyworth/mpp-remote \
    --proxy socks5h://127.0.0.1:8080 \
    "${CLOUDUP_MCP_URL:-https://api.stage-cloudup.com/mcp/public}"
