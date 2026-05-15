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

### 2. Provision a wallet

Pick one of two paths depending on whether there's a human at the keyboard.

#### Path A — Privy agent wallet (dev machines, recommended)

The plugin signs x402 payments by asking Privy's agent-wallet service to sign. The signing key lives in Privy; your machine only holds a per-user authorization keypair in the OS keychain (managed by the Privy CLI itself).

Install the CLI once:

```
npm i -g @privy-io/agent-wallet-cli
```

Then run `/cloudup-setup` in Claude Code — it walks you through `paw login` (browser-based) and prints the Ethereum address of your new wallet.

#### Path B — Local private key (CI, headless, TeamCity)

Path A doesn't work unattended: `paw login` opens a browser, and the session it stores is encrypted with a host-bound key, so you can't `paw login` on your laptop and ship the session to a build agent. For headless contexts, set:

```
export CLOUDUP_WALLET_KEY=0x...   # a fresh secp256k1 key you generated
```

The wrapper skips `paw` entirely and signs locally with viem. Keep the funded balance thin (each upload ≤ `CLOUDUP_MAX_USD`); a leaked key drains exactly what you funded.

### 3. Fund the wallet with USDC

Send testnet USDC to your wallet address on **Base Sepolia** (chain ID 84532). A small amount is plenty — each upload costs ~$0.05. The Cloudup server submits the meta-transaction on your behalf, so you don't need ETH for gas.

For Path A, `paw fund` opens Privy's funding flow in a browser. Or use a Base Sepolia faucet (same source for either path):

- [Circle USDC faucet](https://faucet.circle.com/) — primary (USDC-only is sufficient)
- [Coinbase CDP faucet](https://portal.cdp.coinbase.com/products/faucet) — fallback (ETH + USDC)

### 4. Optional configuration

| Variable | Default | Purpose |
|---|---|---|
| `CLOUDUP_MAX_USD` | `0.20` | Spending cap per upload — refuses to sign above this. Default covers the large-file `begin_upload` SKU (~$0.20); raise if you'll upload bigger payloads. |
| `CLOUDUP_MCP_URL` | `https://api.stage-cloudup.com/mcp/public` | Server endpoint (swap for prod when available) |
| `CLOUDUP_WALLET_KEY` | _(unset)_ | Path B selector. If set to a `0x…` private key, skip `paw` and sign locally. Use for CI / headless agents only. |

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

When the agent calls the upload tool, the MCP server requests an upload from Cloudup. Cloudup responds with an [x402](https://x402.org) payment challenge. mpp-remote builds an [EIP-3009](https://eips.ethereum.org/EIPS/eip-3009) `transferWithAuthorization`; the signature comes from `paw` (Path A — Privy holds the key) or from a local viem signer (Path B — `CLOUDUP_WALLET_KEY` holds the key). mpp-remote retries the original request with an `X-PAYMENT` header carrying that signature; Cloudup settles the payment on-chain and returns the share URL. Total time: a few seconds.

You only need USDC — no ETH for gas. The server submits the meta-transaction on your behalf.

## Troubleshooting

- **`/mcp` doesn't list `cloudup` at all** — Most often a duplicate-suppression collision: an existing manually-configured MCP server (in `~/.claude.json` or via `claude mcp add`) has the same `command + args` as the plugin's, and Claude Code drops the plugin's silently. Run `claude mcp list` to find duplicates, then `claude mcp remove <name>`. See step 5.
- **`/mcp` shows `cloudup` as "Failed to connect"** — On Path A: `paw` isn't installed (`npm i -g @privy-io/agent-wallet-cli`), or the user isn't logged in (`paw login`), or `npx`/`paw` aren't on PATH for non-interactive shells (add their dir to `~/.zshenv`). On Path B: `CLOUDUP_WALLET_KEY` malformed. Verify with `paw list-wallets` from a plain terminal; the wrapper exits with a specific error message in each case.
- **"connection timed out after 30000ms"** — The MCP server is reachable but the upstream Cloudup endpoint isn't. Your A8c SSH tunnel (`ssh -D 8080 …`) isn't up on `localhost:8080`. Bring it back up — see the staging-endpoint section below.
- **"Spending cap exceeded"** — A single upload would exceed `CLOUDUP_MAX_USD`. Raise it (with care) or use a smaller file.
- **"Insufficient balance"** — Fund the wallet address with more testnet USDC on Base Sepolia (`paw fund` or a faucet).

## Reaching the staging endpoint (A8c-only for now)

`v0.1` ships against the Cloudup **staging** endpoint, which is IP-restricted to the Automattic network. The plugin handles this automatically by passing `--proxy socks5h://127.0.0.1:8080` to mpp-remote — the conventional A8c SOCKS5 forwarder (`ssh -D 8080 <a8c-bastion>`). Keep that SSH tunnel up and the plugin will route upstream calls through it.

`socks5h://` (not `socks5://`) is used so DNS resolution happens server-side — internal cloudup hostnames may not be resolvable from your machine.

## Caveats

External developers can install the plugin but will not be able to reach the server until a public/prod endpoint is available. Prod endpoint and a `/cloudup-balance` command are planned for v0.3.

## Version

`0.2.0` — **breaking change.** Two signer paths now: **Path A** (default, dev machines) signs via `@privy-io/agent-wallet-cli` (`paw`), with the key held in Privy and a per-user authorization keypair in the OS keychain. **Path B** (CI / headless) takes a raw `0x…` private key in `CLOUDUP_WALLET_KEY` and signs locally with viem — Path A's browser-based `paw login` can't run unattended, and its session is host-bound. Existing setups must migrate: either install paw (`npm i -g @privy-io/agent-wallet-cli && paw login`) or move their old Keychain key into the `CLOUDUP_WALLET_KEY` env var. The old `scripts/cloudup-key.sh` (Keychain key-management helper) is gone.

## License

MIT.
