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

### 2. Provision a wallet key into Keychain

Run `/cloudup-setup` in Claude Code. It will generate (or import) a wallet private key and store it in your **macOS Keychain** under `service=cloudup, account=wallet`. The key never lives in an environment variable, shell history, or settings file.

Behind the scenes this calls `scripts/cloudup-key.sh`, which you can also invoke directly:

```
~/.claude/plugins/cache/cloudup-plugin/cloudup/*/scripts/cloudup-key.sh generate
~/.claude/plugins/cache/cloudup-plugin/cloudup/*/scripts/cloudup-key.sh status
~/.claude/plugins/cache/cloudup-plugin/cloudup/*/scripts/cloudup-key.sh address
~/.claude/plugins/cache/cloudup-plugin/cloudup/*/scripts/cloudup-key.sh remove
```

The setup flow prints the wallet address. Note it down for step 3.

> **Back-compat:** if `CLOUDUP_WALLET_KEY` is set in your environment, the wrapper still honors it and skips Keychain. Existing setups continue to work; Keychain is the new recommended path.

### 3. Fund the wallet with USDC

Send testnet USDC to the address from step 2 on **Base Sepolia** (chain ID 84532). A small amount is plenty — each upload costs ~$0.05.

Faucets:

- [Circle USDC faucet](https://faucet.circle.com/) — primary (USDC-only is sufficient)
- [Coinbase CDP faucet](https://portal.cdp.coinbase.com/products/faucet) — fallback (ETH + USDC)

You do **not** need ETH for gas — the Cloudup server submits the meta-transaction on your behalf.

### 4. Optional configuration

| Variable | Default | Purpose |
|---|---|---|
| `CLOUDUP_MAX_USD` | `0.20` | Spending cap per upload — refuses to sign above this. Default covers the large-file `begin_upload` SKU (~$0.20); raise if you'll upload bigger payloads. |
| `CLOUDUP_MCP_URL` | `https://api.stage-cloudup.com/mcp/public` | Server endpoint (swap for prod when available) |
| `CLOUDUP_WALLET_KEY` | _(unset)_ | Back-compat: raw private key. If set, overrides Keychain. Not recommended. |

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
- **`/mcp` shows `cloudup` as "Failed to connect"** — Usually means no key has been provisioned yet. Run `/cloudup-setup` (or `scripts/cloudup-key.sh generate` directly) and start a fresh session. You can verify with `scripts/cloudup-key.sh status`.
- **Keychain prompt every session** — macOS sometimes asks to "allow `bash` to access `cloudup`". Click "Always Allow" once; the prompt won't return.
- **"connection timed out after 30000ms"** — The MCP server is reachable but the upstream Cloudup endpoint isn't. Your A8c SSH tunnel (`ssh -D 8080 …`) isn't up on `localhost:8080`. Bring it back up — see the staging-endpoint section below.
- **"Spending cap exceeded"** — A single upload would exceed `CLOUDUP_MAX_USD`. Raise it (with care) or use a smaller file.
- **"Insufficient balance"** — Fund the wallet address with more testnet USDC on Base Sepolia.

## Reaching the staging endpoint (A8c-only for now)

`v0.1` ships against the Cloudup **staging** endpoint, which is IP-restricted to the Automattic network. The plugin handles this automatically by passing `--proxy socks5h://127.0.0.1:8080` to mpp-remote — the conventional A8c SOCKS5 forwarder (`ssh -D 8080 <a8c-bastion>`). Keep that SSH tunnel up and the plugin will route upstream calls through it.

`socks5h://` (not `socks5://`) is used so DNS resolution happens server-side — internal cloudup hostnames may not be resolvable from your machine.

## Caveats

External developers can install the plugin but will not be able to reach the server until a public/prod endpoint is available. Prod endpoint, a generated-wallet setup flow, and a `/cloudup-balance` command are planned for v0.2.

## Version

`0.1.9` — raised the default `CLOUDUP_MAX_USD` from `0.10` to `0.20` so the large-file `begin_upload` SKU (~$0.20) works out of the box without manual env-var override.

## License

MIT.
