---
name: cloudup-setup
description: One-time setup for the Cloudup plugin — provisions a wallet key into macOS Keychain.
---

# /cloudup-setup

One-time setup. Stores a wallet private key in the macOS Keychain so the plugin never reads it from an environment variable or settings file.

## Instructions

1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/cloudup-key.sh status` via Bash. If a key is already stored, ask the user whether to keep it or replace it. If they want to keep it, stop here.
2. Otherwise, ask the user whether to (a) generate a new wallet, or (b) import an existing 0x-prefixed key. Default: (a).
3. **If (a) — generate:** run `${CLAUDE_PLUGIN_ROOT}/scripts/cloudup-key.sh generate` via Bash. Print the wallet address and faucet URLs from the output.
4. **If (b) — import:** tell the user to paste the key themselves using the `! <command>` prefix so the key doesn't land in conversation history. The command they should type is:
   ```
   ! ${CLAUDE_PLUGIN_ROOT}/scripts/cloudup-key.sh set 0x...
   ```
   Wait for them to run it before continuing.
5. Confirm by running `${CLAUDE_PLUGIN_ROOT}/scripts/cloudup-key.sh address`. Print the address and remind the user to fund it with Base Sepolia USDC.
6. Tell the user to restart Claude Code — the MCP server picks up the new Keychain entry at session start.
