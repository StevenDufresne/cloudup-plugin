#!/usr/bin/env bash
# Manage the Cloudup wallet key in the macOS Keychain.
#
# Subcommands:
#   set <0x-key>   store a specific key
#   generate       generate a fresh key, store it, print the address
#   show           print the stored key (use with care — it's a private key)
#   address        print the wallet address derived from the stored key
#   remove         delete the stored key
#   status         report whether a key is stored

set -euo pipefail

SERVICE="cloudup"
ACCOUNT="wallet"

require_macos() {
    if ! command -v security >/dev/null 2>&1; then
        echo "cloudup-key: requires macOS Keychain (security CLI not found)" >&2
        exit 2
    fi
}

VIEM_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/cloudup"

# Install viem once into a stable cache dir so `node -e` can require() it.
# `npx -p viem -- node -e ...` does not work because npx only puts the
# package's bins on PATH, not in node's resolution path.
ensure_viem() {
    if [ -d "$VIEM_CACHE/node_modules/viem" ]; then
        return 0
    fi
    mkdir -p "$VIEM_CACHE"
    (cd "$VIEM_CACHE" \
        && printf '{"name":"cloudup-key-helper","private":true,"dependencies":{"viem":"latest"}}\n' > package.json \
        && npm install --silent --no-audit --no-fund >&2)
}

derive_address() {
    local key="$1"
    ensure_viem >&2 || return 1
    (cd "$VIEM_CACHE" && node -e "console.log(require('viem/accounts').privateKeyToAccount('$key').address)")
}

generate_key() {
    # 32 random bytes is a valid secp256k1 private key with overwhelming
    # probability (chance of being >= curve order is < 2^-128).
    if command -v openssl >/dev/null 2>&1; then
        printf '0x%s\n' "$(openssl rand -hex 32)"
    else
        node -e "console.log('0x' + require('crypto').randomBytes(32).toString('hex'))"
    fi
}

store() {
    local key="$1"
    if [[ ! "$key" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        echo "cloudup-key: key must be a 0x-prefixed 32-byte hex string" >&2
        exit 1
    fi
    security add-generic-password -s "$SERVICE" -a "$ACCOUNT" -w "$key" -U >/dev/null
}

cmd="${1:-status}"

case "$cmd" in
    set)
        require_macos
        if [ $# -lt 2 ]; then
            echo "Usage: cloudup-key set <0x-key>" >&2
            exit 2
        fi
        store "$2"
        echo "Stored key in macOS Keychain ($SERVICE/$ACCOUNT)."
        addr="$(derive_address "$2" || true)"
        if [ -n "$addr" ]; then
            echo "Wallet address: $addr"
            echo "Fund this address with Base Sepolia USDC."
        fi
        ;;

    generate)
        require_macos
        key="$(generate_key)"
        store "$key"
        echo "Generated new wallet and stored in macOS Keychain ($SERVICE/$ACCOUNT)."
        addr="$(derive_address "$key" || true)"
        if [ -n "$addr" ]; then
            echo "Wallet address: $addr"
            echo "Fund this address with Base Sepolia USDC:"
            echo "  https://faucet.circle.com/"
            echo "  https://portal.cdp.coinbase.com/products/faucet"
        else
            echo "Key stored, but address derivation failed."
            echo "Run \`cloudup-key.sh address\` to retry derivation."
        fi
        ;;

    show)
        require_macos
        security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w
        ;;

    address)
        require_macos
        key="$(security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w 2>/dev/null)" || {
            echo "cloudup-key: no key stored" >&2
            exit 1
        }
        derive_address "$key"
        ;;

    remove)
        require_macos
        security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null
        echo "Removed key from macOS Keychain."
        ;;

    status)
        require_macos
        if security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w >/dev/null 2>&1; then
            echo "Key stored in macOS Keychain ($SERVICE/$ACCOUNT)."
        else
            echo "No key stored."
            exit 1
        fi
        ;;

    *)
        cat >&2 <<EOF
Usage: cloudup-key <command>
  set <0x-key>   store a specific key
  generate       generate a fresh key, store it, print the address
  show           print the stored key
  address        print the wallet address
  remove         delete the stored key
  status         report whether a key is stored
EOF
        exit 2
        ;;
esac
