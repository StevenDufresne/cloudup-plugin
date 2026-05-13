# Cloudup Plugin (v1) — Design

**Status:** draft, pending user review
**Date:** 2026-05-13
**Repo:** `~/dev/cloudup-plugin`

## Purpose

Ship a Claude Code plugin that lets agents upload images — typically Playwright screenshots taken during UI verification — to Cloudup and embed the returned URL in PR comments, issues, and chat replies. Payment uses x402 micropayments from a user-provided wallet.

Today, agents that take Playwright screenshots have no easy way to share them: PR markdown wants a URL, the screenshot lives on local disk, and nothing connects the two. This plugin closes that gap as a single install.

## Scope (v1)

**In scope:**
- Claude Code plugin package (`plugin.json`, `.mcp.json`, `skills/`, `commands/`, `README.md`)
- MCP server declaration that wraps `tellyworth/mpp-remote` pointed at Cloudup staging
- A skill that teaches the agent when to upload and how to embed the resulting URL
- A `/cloudup <path>` slash command for explicit uploads
- BYO private key via host environment variable
- README walking the user through key generation, USDC funding, and env setup

**Out of scope:**
- Wallet generation, storage, or backup (user brings their own key)
- Screenshot capture tooling (agents use Playwright, `screencapture`, etc., as they already do)
- Annotation / editing
- Production Cloudup endpoint (staging only in v1)
- Marketplace listing (git-URL install is acceptable for v1)
- Automated tests (v1 is config glue; revisit if surface area grows)

## Architecture

The plugin (`plugin.json` `name: "cloudup"`) is a thin packaging layer. Three artifacts do the work:

1. **`.mcp.json`** declares one MCP server named `cloudup`. Invocation:
   ```
   npx -y github:tellyworth/mpp-remote#<pinned-sha> ${CLOUDUP_MCP_URL:-https://api.stage-cloudup.com/mcp/public}
   ```
   Env passed to the server:
   - `MPP_WALLET_PRIVATE_KEY` ← `${CLOUDUP_WALLET_KEY}` (required)
   - `MPP_MAX_AMOUNT_USD` ← `${CLOUDUP_MAX_USD:-0.10}` (default $0.10)

2. **`skills/uploading-to-cloudup/SKILL.md`** — activates when the agent has captured an image and needs a hosted URL for a PR comment, issue reply, or chat response. Tells the agent to call `cloudup__quick_upload`, embed the returned URL as `![alt](url)`, and disclose to the user that an x402 micropayment was made. Narrow scope: does not volunteer to upload arbitrary generated images.

3. **`commands/cloudup.md`** — implements `/cloudup <path>` for explicit user-driven uploads. Useful for testing and for users who want manual control.

User-side setup (one-time, documented in README):
1. Generate a private key (snippet: `cast wallet new` or `node -e "console.log(require('viem/accounts').generatePrivateKey())"`)
2. Fund the resulting address with USDC on the chain Cloudup staging accepts
3. `export CLOUDUP_WALLET_KEY=0x...` in shell rc, or set it in Claude Code settings.json under `env`
4. Optional: `CLOUDUP_MAX_USD` (default $0.10), `CLOUDUP_MCP_URL` (default staging)

## Data flow

1. Agent runs Playwright, captures screenshot to `/tmp/foo.png` during UI verification
2. Agent needs to reference the image in a PR comment → skill activates → agent calls `cloudup__quick_upload(path=/tmp/foo.png)`
3. MCP server (mpp-remote) issues the upload request → Cloudup returns x402 challenge
4. mpp-remote signs an EIP-3009 `transferWithAuthorization` with the loaded private key, retries with the `X-PAYMENT` header
5. Cloudup settles on-chain, returns share URL
6. Agent receives URL in MCP tool response, embeds it as `![alt](url)` in the PR comment, surfaces to user that an upload was paid for

## Failure modes

| Failure | Surface |
|---|---|
| `CLOUDUP_WALLET_KEY` not set | MCP server start fails → skill instructs agent to point user at README setup section |
| Insufficient USDC balance | mpp-remote returns settlement failure → agent reports balance issue (no built-in balance check in v1) |
| Spending cap exceeded | `MPP_MAX_AMOUNT_USD` refuses → agent reports cap was hit, user can raise via env |
| Network / upload error | Standard MCP error surfaced to agent |

## Project structure

```
~/dev/cloudup-plugin/
  README.md
  plugin.json
  .mcp.json
  skills/
    uploading-to-cloudup/
      SKILL.md
  commands/
    cloudup.md
  docs/
    superpowers/
      specs/
        2026-05-13-cloudup-plugin-design.md
```

## Testing strategy (v1)

Manual end-to-end only:

1. Install plugin locally via `claude plugin install` against the local path
2. Set `CLOUDUP_WALLET_KEY` to a funded staging wallet
3. Ask the agent to take a Playwright screenshot of any URL and embed it in a draft PR comment
4. Verify the returned URL resolves to the uploaded image

No unit tests in v1 — the plugin is configuration glue. If we add a wrapper script or non-trivial code path later, add tests then.

## Known unknowns to resolve during scaffolding

- **Plugin `.mcp.json` env var expansion.** This spec assumes `${VAR}` expansion works in plugin-shipped `.mcp.json`. If it doesn't, the README falls back to "paste this block into your settings.json" and the plugin ships skill + command only.
- **mpp-remote pin SHA.** Need to pick a specific commit of `tellyworth/mpp-remote` known to work with Cloudup staging x402.
- **Chain / asset for staging.** Need to confirm which chain and USDC variant Cloudup staging accepts (likely a testnet variant) so the README funding instructions are accurate.

## Decisions log

- **BYO key, not generated.** Keeps v1 tiny; defers custody and onboarding UX to a possible v2.
- **Staging endpoint, not prod.** Prod x402 not confirmed live; staging is the tested path.
- **Narrow skill scope.** Avoids charging users for unwanted uploads — agent only reaches for the tool when there's a real need to share an image.
- **`$0.10` cap default.** Low enough to fail loud on accidental usage, high enough for typical uploads.
- **Pinned `mpp-remote` SHA, not HEAD.** Stability over latest features; bumped via plugin releases.

## Deferred to v2+

- Production Cloudup endpoint (when x402 prod is live)
- Generated wallet onboarding (`/cloudup-setup` command that creates and stores a key locally)
- `/cloudup-balance` status command
- Marketplace listing
- Automated end-to-end tests against a stub MCP server
