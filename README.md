# Cloudup Plugin for Claude Code

Upload images to Cloudup directly from Claude Code, paying per upload with x402 micropayments. Agents can capture screenshots (e.g. via Playwright) and embed shareable URLs in PR comments, issues, and chat replies.

## What's in the plugin

- **MCP server** (`cloudup`) — wraps `tellyworth/mpp-remote` pointed at Cloudup staging
- **Skill** (`uploading-to-cloudup`) — teaches the agent when to reach for the upload tool
- **Slash command** (`/cloudup <path>`) — explicit user-driven uploads

## Setup

### 1. Install the plugin

```
claude plugin install <git-url-or-path-to-this-repo>
```

### 2. Generate a wallet private key

Any EVM private key works. To generate one quickly:

```
node -e "console.log(require('viem/accounts').generatePrivateKey())"
```

Save the resulting `0x…` string somewhere safe. Keep it secret.

### 3. Fund the wallet with USDC

Find the address corresponding to your private key (e.g. via `cast wallet address <KEY>` or any wallet client).

Send USDC to that address on **Base Sepolia** (testnet, chain ID 84532). A small amount of test USDC is plenty — each upload costs ~$0.05.

Faucets:

- [Circle USDC faucet](https://faucet.circle.com/) — primary (USDC-only is sufficient)
- [Coinbase CDP faucet](https://portal.cdp.coinbase.com/products/faucet) — fallback (ETH + USDC)

You do **not** need ETH for gas — the Cloudup server submits the meta-transaction on your behalf.

### 4. Configure environment variables

Set `CLOUDUP_WALLET_KEY` so the MCP server can sign payments. The simplest path:

```
# in ~/.zshrc or ~/.bashrc
export CLOUDUP_WALLET_KEY=0x...
```

Or via Claude Code settings (`~/.claude/settings.json`):

```json
{
  "env": {
    "CLOUDUP_WALLET_KEY": "0x..."
  }
}
```

Optional overrides:

| Variable | Default | Purpose |
|---|---|---|
| `CLOUDUP_MAX_USD` | `0.10` | Spending cap per upload — refuses to sign above this |
| `CLOUDUP_MCP_URL` | `https://api.stage-cloudup.com/mcp/public` | Server endpoint (swap for prod when available) |

### 5. Try it

In a Claude Code session:

```
/cloudup /tmp/screenshot.png
```

Or let the agent reach for it naturally: ask it to take a Playwright screenshot of any URL and embed the result in a draft PR comment. The skill will trigger and the URL will appear in markdown.

## How it works

When the agent calls the upload tool, the MCP server requests an upload from Cloudup. Cloudup responds with an [x402](https://x402.org) payment challenge. The server signs an [EIP-3009](https://eips.ethereum.org/EIPS/eip-3009) `transferWithAuthorization` with your key and retries with an `X-PAYMENT` header. Cloudup settles the payment on-chain and returns the share URL. Total time: a few seconds.

You only need USDC — no ETH for gas. The server submits the meta-transaction on your behalf.

## Troubleshooting

- **"CLOUDUP_WALLET_KEY is not set"** — Run `echo $CLOUDUP_WALLET_KEY` in a fresh shell. If empty, your shell rc isn't being loaded by Claude Code. Set it in `~/.claude/settings.json` under `env` instead.
- **"Spending cap exceeded"** — A single upload would exceed `CLOUDUP_MAX_USD`. Raise it (with care) or pick a smaller file.
- **"Insufficient balance"** — Fund the wallet address with more USDC on the correct chain.
- **MCP server not starting** — Run the plugin's wrapper script directly with `CLOUDUP_WALLET_KEY` set (path: `~/.claude/plugins/<marketplace>/cloudup/scripts/cloudup-server.sh`). That surfaces npx or network errors directly.

## Version

`0.1.0` — staging endpoint only. Prod endpoint, generated-wallet setup, and a balance command are planned for v0.2.

## License

MIT.
