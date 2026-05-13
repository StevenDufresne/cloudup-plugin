# Cloudup Plugin for Claude Code

Upload images to Cloudup directly from Claude Code, paying per upload with x402 micropayments. Agents can capture screenshots (e.g. via Playwright) and embed shareable URLs in PR comments, issues, and chat replies.

## What's in the plugin

- **MCP server** (`cloudup`) — wraps `tellyworth/mpp-remote` pointed at Cloudup staging
- **Skill** (`uploading-to-cloudup`) — teaches the agent when to reach for the upload tool
- **Slash command** (`/cloudup <path>`) — explicit user-driven uploads

## Setup

### 1. Install the plugin

In a Claude Code session:

```
/plugin marketplace add StevenDufresne/cloudup-plugin
/plugin install cloudup@cloudup-plugin
```

### 2. Generate a wallet private key

Any EVM private key works. To generate one quickly:

```
node -e "console.log(require('viem/accounts').generatePrivateKey())"
```

Save the resulting `0x…` string somewhere safe. Keep it secret.

### 3. Fund the wallet with USDC

Find the address corresponding to your private key (e.g. via `cast wallet address <KEY>` or any wallet client).

Send testnet USDC to that address on **Base Sepolia** (chain ID 84532). A small amount is plenty — each upload costs ~$0.05.

Faucets:

- [Circle USDC faucet](https://faucet.circle.com/) — primary (USDC-only is sufficient)
- [Coinbase CDP faucet](https://portal.cdp.coinbase.com/products/faucet) — fallback (ETH + USDC)

You do **not** need ETH for gas — the Cloudup server submits the meta-transaction on your behalf.

### 4. Export the key in your shell

```
# in ~/.zshrc or ~/.bashrc
export CLOUDUP_WALLET_KEY=0x...
```

Reload your shell so the variable is available before you start Claude Code.

Optional overrides:

| Variable | Default | Purpose |
|---|---|---|
| `CLOUDUP_MAX_USD` | `0.10` | Spending cap per upload — refuses to sign above this |
| `CLOUDUP_MCP_URL` | `https://api.stage-cloudup.com/mcp/public` | Server endpoint (swap for prod when available) |

### 5. Remove any duplicate manual cloudup MCP

If you previously registered an `mpp-remote`-backed Cloudup MCP server manually (e.g. via `claude mcp add`), remove it. Claude Code silently suppresses plugin-declared MCP servers whose command + args match an existing manually-configured one, so the plugin's `cloudup` will appear to "do nothing" if a manual duplicate exists.

```
claude mcp list                                # find any manual cloudup-* entries
claude mcp remove <your-cloudup-server-name>
```

### 6. Restart Claude Code and verify

Start a fresh Claude Code session. Run `/mcp` and confirm `cloudup` shows as connected. Then test:

```
/cloudup /tmp/screenshot.png
```

Or let the agent reach for it naturally: ask it to take a Playwright screenshot of any URL and embed the result in a draft PR comment. The skill will trigger and the URL will appear in markdown.

## How it works

When the agent calls the upload tool, the MCP server requests an upload from Cloudup. Cloudup responds with an [x402](https://x402.org) payment challenge. The server signs an [EIP-3009](https://eips.ethereum.org/EIPS/eip-3009) `transferWithAuthorization` with your key and retries with an `X-PAYMENT` header. Cloudup settles the payment on-chain and returns the share URL. Total time: a few seconds.

You only need USDC — no ETH for gas. The server submits the meta-transaction on your behalf.

## Troubleshooting

- **`/mcp` doesn't list `cloudup` at all** — Most often a duplicate-suppression collision: an existing manually-configured MCP server (in `~/.claude.json` or via `claude mcp add`) has the same `command + args` as the plugin's, and Claude Code drops the plugin's silently. Run `claude mcp list` to find duplicates, then `claude mcp remove <name>`. See step 5.
- **`/mcp` shows `cloudup` as "Failed to connect"** — Usually means `CLOUDUP_WALLET_KEY` isn't set in the environment Claude Code launched from. Set it in your shell rc, reload, and start a fresh session. Or set it in `~/.claude/settings.json` under `env` if your shell rc isn't being picked up by Claude Code.
- **"Spending cap exceeded"** — A single upload would exceed `CLOUDUP_MAX_USD`. Raise it (with care) or use a smaller file.
- **"Insufficient balance"** — Fund the wallet address with more testnet USDC on Base Sepolia.

## Caveats

`v0.1` ships against the Cloudup **staging** endpoint, which is currently IP-restricted to the Automattic network. External developers can install the plugin but will not be able to reach the server until a public/prod endpoint is available. Prod endpoint, a generated-wallet setup flow, and a `/cloudup-balance` command are planned for v0.2.

## Version

`0.1.5`

## License

MIT.
