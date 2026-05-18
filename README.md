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

Three paths; `/cloudup-setup` walks you through A or B interactively. C is the build-agent escape hatch.

#### Path A — Privy agent wallet (recommended)

The plugin asks Privy's agent-wallet service to sign each x402 payment. The signing key lives in Privy; your machine only holds a per-user authorization keypair in the OS keychain (managed by the Privy CLI itself).

Install the CLI once:

```
npm i -g @privy-io/agent-wallet-cli
```

Then run `/cloudup-setup` in Claude Code, pick **Privy agent wallet**, and it walks you through `paw login` (browser-based) and prints the Ethereum address of your new wallet.

#### Path B — Locally generated key (macOS, laptop)

A fresh secp256k1 key generated on your machine and stored in the macOS Keychain. You hold the key — no third-party custody, but also no recovery if the laptop is lost. macOS only today.

Run `/cloudup-setup` in Claude Code and pick **Locally generated key**. It runs `scripts/cloudup-key.sh generate`, which generates the key, stores it under Keychain service `cloudup` / account `wallet`, and prints the derived address to fund. Manage the stored key with the same script:

```
scripts/cloudup-key.sh status     # is a key stored?
scripts/cloudup-key.sh address    # print the wallet address
scripts/cloudup-key.sh show       # print the private key (use with care)
scripts/cloudup-key.sh remove     # delete the key from Keychain
```

#### Path C — `CLOUDUP_WALLET_KEY` env var (CI, headless, TeamCity)

Paths A and B both require interactive setup that doesn't work on a build agent: `paw login` is browser-based, and macOS Keychain doesn't exist. For headless contexts, set:

```
export CLOUDUP_WALLET_KEY=0x...   # a fresh secp256k1 key you generated
```

The wrapper skips Privy and Keychain entirely and signs locally with viem. Keep the funded balance thin (each upload ≤ `CLOUDUP_MAX_USD`); a leaked key drains exactly what you funded.

**Signer precedence in the wrapper:** if `CLOUDUP_WALLET_KEY` is set it wins (CI path). Otherwise a Keychain-stored key wins if present (Path B). Otherwise the wrapper falls back to `paw` (Path A). Switching between B and A on the same machine requires removing the previous one's state first — `scripts/cloudup-key.sh remove` to drop the Keychain key, or clear the paw session.

### 3. Fund the wallet with USDC

Send testnet USDC to your wallet address on **Base Sepolia** (chain ID 84532). A small amount is plenty — uploads cost $0.01–$0.25 depending on which tool the agent uses (image embeds are $0.05, small file uploads $0.01, and large multipart uploads up to $0.25). The Cloudup server submits the meta-transaction on your behalf, so you don't need ETH for gas.

For Path A, `paw fund` opens Privy's funding flow in a browser. For Paths B and C, use a Base Sepolia faucet:

- [Circle USDC faucet](https://faucet.circle.com/) — primary (USDC-only is sufficient)
- [Coinbase CDP faucet](https://portal.cdp.coinbase.com/products/faucet) — fallback (ETH + USDC)

### 4. Optional configuration

| Variable | Default | Purpose |
|---|---|---|
| `CLOUDUP_MAX_USD` | `0.30` | Spending cap per upload — refuses to sign above this. Default covers the `large` SKU (`begin_upload`, $0.25) with a small margin; raise if pricing changes upstream. |
| `CLOUDUP_MCP_URL` | `https://api.stage-cloudup.com/mcp/public` | Server endpoint (swap for prod when available) |
| `CLOUDUP_WALLET_KEY` | _(unset)_ | Path C selector. If set to a `0x…` private key, skip both `paw` and Keychain and sign locally with viem. Use for CI / headless agents only. |

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

When the agent calls the upload tool, the MCP server requests an upload from Cloudup. Cloudup responds with an [x402](https://x402.org) payment challenge. mpp-remote builds an [EIP-3009](https://eips.ethereum.org/EIPS/eip-3009) `transferWithAuthorization`; the signature comes from `paw` (Path A — Privy holds the key), a local viem signer reading the Keychain (Path B), or a local viem signer reading `CLOUDUP_WALLET_KEY` (Path C). mpp-remote retries the original request with an `X-PAYMENT` header carrying that signature; Cloudup settles the payment on-chain and returns the share URL. Total time: a few seconds.

You only need USDC — no ETH for gas. The server submits the meta-transaction on your behalf.

## Troubleshooting

- **`/mcp` doesn't list `cloudup` at all** — Most often a duplicate-suppression collision: an existing manually-configured MCP server (in `~/.claude.json` or via `claude mcp add`) has the same `command + args` as the plugin's, and Claude Code drops the plugin's silently. Run `claude mcp list` to find duplicates, then `claude mcp remove <name>`. See step 5.
- **`/mcp` shows `cloudup` as "Failed to connect"** — On Path A: `paw` isn't installed (`npm i -g @privy-io/agent-wallet-cli`), or the user isn't logged in (`paw login`), or `npx`/`paw` aren't on PATH for non-interactive shells (add their dir to `~/.zshenv`). On Path B: no key in Keychain (`scripts/cloudup-key.sh status` should say "Key stored"). On Path C: `CLOUDUP_WALLET_KEY` malformed. The wrapper exits with a specific error message in each case.
- **"connection timed out after 30000ms"** — The MCP server is reachable but the upstream Cloudup endpoint isn't. Your A8c SSH tunnel (`ssh -D 8080 …`) isn't up on `localhost:8080`. Bring it back up — see the staging-endpoint section below.
- **"Spending cap exceeded"** — A single upload would exceed `CLOUDUP_MAX_USD`. Raise it (with care) or use a smaller file.
- **"Insufficient balance"** — Fund the wallet address with more testnet USDC on Base Sepolia (`paw fund` or a faucet).

## Reaching the staging endpoint (A8c-only for now)

`v0.1` ships against the Cloudup **staging** endpoint, which is IP-restricted to the Automattic network. The plugin handles this automatically by passing `--proxy socks5h://127.0.0.1:8080` to mpp-remote — the conventional A8c SOCKS5 forwarder (`ssh -D 8080 <a8c-bastion>`). Keep that SSH tunnel up and the plugin will route upstream calls through it.

`socks5h://` (not `socks5://`) is used so DNS resolution happens server-side — internal cloudup hostnames may not be resolvable from your machine.

## Caveats

External developers can install the plugin but will not be able to reach the server until a public/prod endpoint is available. Prod endpoint and a `/cloudup-balance` command are planned for v0.3.

## Version

`0.3.0` — Three signer paths, picked at MCP launch in this precedence order:
**Path C** (`CLOUDUP_WALLET_KEY` env var, CI / headless) → **Path B** (macOS Keychain, locally-generated key, managed by `scripts/cloudup-key.sh`) → **Path A** (Privy agent-wallet CLI, browser login). `/cloudup-setup` is now a chooser between A and B; C is documented in the README as the build-agent path. Path B is the v0.1 Keychain helper restored — it was dropped in 0.2.0 when Privy became the only laptop path, and is back so users who don't want third-party custody have a managed-on-machine option.

## License

MIT.
