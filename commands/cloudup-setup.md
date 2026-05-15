---
name: cloudup-setup
description: One-time setup for the Cloudup plugin — installs @privy-io/agent-wallet-cli and logs the user in to Privy.
---

# /cloudup-setup

One-time setup. Provisions a Privy agent wallet via `@privy-io/agent-wallet-cli` (`paw`). The signing key stays in Privy's wallet service; the local machine only holds a per-user authorization keypair in the OS keychain.

## Instructions

1. Check whether `paw` is installed by running `command -v paw` via Bash. If it prints a path, skip to step 3.
2. If `paw` is missing, ask the user to install it themselves so the install isn't tied to this conversation. Tell them to run, in the prompt:
   ```
   ! npm i -g @privy-io/agent-wallet-cli
   ```
   Wait for them to confirm.
3. Run `paw list-wallets` via Bash.
   - If it prints an `Ethereum: 0x…` line, a session already exists. Print the address and tell the user setup is done — they only need to restart Claude Code if this is the first time the plugin's been wired up. Stop here.
   - If it prints `Not logged in. Run \`privy login\` first.`, proceed to step 4.
4. Tell the user to run `paw login` themselves (not via you) so the browser-based auth flow stays interactive:
   ```
   ! paw login
   ```
   The CLI will open a browser, the user signs in, pastes the credentials blob back, and the CLI stores the session in the OS keychain. Wait for them to confirm.
5. Re-run `paw list-wallets` to confirm. Print the Ethereum address and tell the user:
   - Fund this address with **Base Sepolia USDC** for the current (staging) endpoint. They can use `paw fund` to open the on-ramp, or any Base Sepolia faucet.
   - Restart Claude Code so the MCP server picks up the new wallet at session start.
