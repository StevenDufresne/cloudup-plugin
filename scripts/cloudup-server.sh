#!/usr/bin/env bash
# Launches the mpp-remote MCP server pointed at Cloudup with payment env mapped
# from user-friendly CLOUDUP_* variables.

set -euo pipefail

: "${CLOUDUP_WALLET_KEY:?CLOUDUP_WALLET_KEY is not set. See the plugin README for setup.}"

# To bump mpp-remote, update the SHA in the tarball URL below.
exec env \
  MPP_WALLET_PRIVATE_KEY="${CLOUDUP_WALLET_KEY}" \
  MPP_MAX_AMOUNT_USD="${CLOUDUP_MAX_USD:-0.10}" \
  npx -y "https://github.com/tellyworth/mpp-remote/archive/54e42e4a796c42aee81967fce81e1c2f3f58e8c4.tar.gz" \
  "${CLOUDUP_MCP_URL:-https://api.stage-cloudup.com/mcp/public}"
