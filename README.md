# Cloudup Plugin for Claude Code

Upload images to Cloudup directly from Claude Code, paying per upload with x402 micropayments. Agents can capture screenshots (e.g. via Playwright) and embed shareable URLs in PR comments, issues, and chat replies.

## What's in the plugin

- **MCP server** (`cloudup`) — wraps `tellyworth/mpp-remote` pointed at Cloudup staging
- **Skill** (`uploading-to-cloudup`) — teaches the agent when to reach for the upload tool
- **Slash commands** — `/cloudup <path>` for uploads, `/cloudup-setup` for one-time key provisioning

## Setup

### 1. Install the plugin

In a Claude Code session:

```
/plugin marketplace add StevenDufresne/cloudup-plugin
/plugin install cloudup@cloudup-plugin
```

### 2. Install the Privy agent-wallet CLI

The plugin signs x402 payments through Privy's agent-wallet service — the signing key lives in Privy, not on your machine. Install Privy's CLI once:

```
npm i -g @privy-io/agent-wallet-cli
```

This installs two binaries (`paw` and `privy-agent-wallet`); the plugin uses `paw`.

### 3. Run `/cloudup-setup`

In Claude Code: `/cloudup-setup`. It walks you through `paw login` — the CLI opens a browser, you sign in to Privy, paste the credentials blob back, and the CLI stores a per-user authorization keypair in your OS keychain. The actual signing key never leaves Privy.

The setup prints the Ethereum address of your new wallet. Note it down for step 4.

### 4. Fund the wallet with USDC

Send testnet USDC to that address on **Base Sepolia** (chain ID 84532). A small amount is plenty — each upload costs ~$0.05. The Cloudup server submits the meta-transaction on your behalf, so you don't need ETH for gas.

```
paw fund
```

opens Privy's funding flow in a browser. Alternatively, use any Base Sepolia faucet:

- [Circle USDC faucet](https://faucet.circle.com/) — primary (USDC-only is sufficient)
- [Coinbase CDP faucet](https://portal.cdp.coinbase.com/products/faucet) — fallback (ETH + USDC)

### 5. Optional configuration

| Variable | Default | Purpose |
|---|---|---|
| `CLOUDUP_MAX_USD` | `0.20` | Spending cap per upload — refuses to sign above this. Default covers the large-file `begin_upload` SKU (~$0.20); raise if you'll upload bigger payloads. |
| `CLOUDUP_MCP_URL` | `https://api.stage-cloudup.com/mcp/public` | Server endpoint (swap for prod when available) |

### 6. Remove any duplicate manual cloudup MCP

If you previously registered an `mpp-remote`-backed Cloudup MCP server manually (e.g. via `claude mcp add`), remove it. Claude Code silently suppresses plugin-declared MCP servers whose command + args match an existing manually-configured one, so the plugin's `cloudup` will appear to "do nothing" if a manual duplicate exists.

```
claude mcp list                                # find any manual cloudup-* entries
claude mcp remove <your-cloudup-server-name>
```

### 7. Restart Claude Code and verify

Start a fresh Claude Code session. Run `/mcp` and confirm `cloudup` shows as connected. Then test:

```
/cloudup /tmp/screenshot.png
```

Or let the agent reach for it naturally: ask it to take a Playwright screenshot of any URL and embed the result in a draft PR comment. The skill will trigger and the URL will appear in markdown.

## How it works

When the agent calls the upload tool, the MCP server requests an upload from Cloudup. Cloudup responds with an [x402](https://x402.org) payment challenge. mpp-remote builds an [EIP-3009](https://eips.ethereum.org/EIPS/eip-3009) `transferWithAuthorization` and asks `paw` (the Privy agent-wallet CLI) to sign it — Privy holds the signing key and returns just the signature. mpp-remote retries the original request with an `X-PAYMENT` header carrying that signature; Cloudup settles the payment on-chain and returns the share URL. Total time: a few seconds.

You only need USDC — no ETH for gas. The server submits the meta-transaction on your behalf.

## Troubleshooting

- **`/mcp` doesn't list `cloudup` at all** — Most often a duplicate-suppression collision: an existing manually-configured MCP server (in `~/.claude.json` or via `claude mcp add`) has the same `command + args` as the plugin's, and Claude Code drops the plugin's silently. Run `claude mcp list` to find duplicates, then `claude mcp remove <name>`. See step 6.
- **`/mcp` shows `cloudup` as "Failed to connect"** — Usually one of: `paw` isn't installed (`npm i -g @privy-io/agent-wallet-cli`), or the user isn't logged in (`paw login`), or `npx`/`paw` aren't on PATH for non-interactive shells (add their dir to `~/.zshenv`). Verify with `paw list-wallets` from a plain terminal; the wrapper exits with a specific error message in each case.
- **"connection timed out after 30000ms"** — The MCP server is reachable but the upstream Cloudup endpoint isn't. Your A8c SSH tunnel (`ssh -D 8080 …`) isn't up on `localhost:8080`. Bring it back up — see the staging-endpoint section below.
- **"Spending cap exceeded"** — A single upload would exceed `CLOUDUP_MAX_USD`. Raise it (with care) or use a smaller file.
- **"Insufficient balance"** — Fund the wallet address with more testnet USDC on Base Sepolia (`paw fund` or a faucet).

## Reaching the staging endpoint (A8c-only for now)

`v0.1` ships against the Cloudup **staging** endpoint, which is IP-restricted to the Automattic network. The plugin handles this automatically by passing `--proxy socks5h://127.0.0.1:8080` to mpp-remote — the conventional A8c SOCKS5 forwarder (`ssh -D 8080 <a8c-bastion>`). Keep that SSH tunnel up and the plugin will route upstream calls through it.

`socks5h://` (not `socks5://`) is used so DNS resolution happens server-side — internal cloudup hostnames may not be resolvable from your machine.

## Caveats

External developers can install the plugin but will not be able to reach the server until a public/prod endpoint is available. Prod endpoint and a `/cloudup-balance` command are planned for v0.3.

## Version

`0.2.0` — **breaking change.** Wallet signing moves from local-key (Keychain-stored `0x…` private key) to Privy's agent-wallet CLI (`@privy-io/agent-wallet-cli`). The signing key now lives in Privy's wallet service; the local machine only holds a per-user authorization keypair in the OS keychain. Existing users must reinstall: `npm i -g @privy-io/agent-wallet-cli && paw login`. The legacy `scripts/cloudup-key.sh` and the `CLOUDUP_WALLET_KEY` env override are gone.

## License

MIT.
