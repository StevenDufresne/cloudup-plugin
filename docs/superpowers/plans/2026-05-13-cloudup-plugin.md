# Cloudup Plugin v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Claude Code plugin that lets agents upload images to Cloudup via x402 micropayments and embed the returned URL in PRs, issues, and chat.

**Architecture:** Plugin packages three artifacts — an MCP server declaration (thin wrapper over `tellyworth/mpp-remote`), a skill teaching agents when/how to upload, and a `/cloudup` slash command. The MCP server is launched through a wrapper shell script so the plugin can map user-friendly env vars (`CLOUDUP_WALLET_KEY`, `CLOUDUP_MAX_USD`, `CLOUDUP_MCP_URL`) onto mpp-remote's expected names without depending on JSON env-var expansion.

**Tech Stack:** JSON manifests, Markdown skills/commands, Bash wrapper script, `npx`-launched Node MCP server.

**Spec reference:** `docs/superpowers/specs/2026-05-13-cloudup-plugin-design.md`

---

## File Structure

Files to create in `~/dev/cloudup-plugin`:

| File | Responsibility |
|---|---|
| `.claude-plugin/plugin.json` | Plugin metadata (name, version, description, author) — discovered by Claude Code |
| `.claude-plugin/marketplace.json` | Marketplace manifest listing this single plugin so `claude plugin install` against the repo works |
| `.mcp.json` | Declares the `cloudup` MCP server pointing at the wrapper script |
| `scripts/cloudup-server.sh` | Wrapper that maps user env vars to mpp-remote env vars and execs `npx ... mpp-remote` |
| `skills/uploading-to-cloudup/SKILL.md` | Teaches the agent when to upload + how to embed the URL |
| `commands/cloudup.md` | `/cloudup <path>` for explicit user-driven uploads |
| `README.md` | Setup walkthrough: install, generate key, fund USDC, configure env |

Already exists (do not modify):
- `docs/superpowers/specs/2026-05-13-cloudup-plugin-design.md`

---

## Task 1: Resolve mpp-remote pin SHA

**Files:** none (research output captured in later tasks)

The plugin should pin to a specific commit of `tellyworth/mpp-remote` rather than HEAD so reinstalls are stable.

- [ ] **Step 1: Fetch latest commit on default branch**

Run:
```bash
gh api repos/tellyworth/mpp-remote/commits/HEAD --jq '.sha'
```

Expected: 40-character SHA string. Save this — you'll use it as `<MPP_REMOTE_SHA>` in later tasks.

- [ ] **Step 2: Verify the SHA exists and the repo is reachable**

Run:
```bash
gh api repos/tellyworth/mpp-remote/commits/<MPP_REMOTE_SHA> --jq '.commit.message' | head -3
```

Expected: a commit message prints. If the call fails or the repo is private, stop and surface the blocker — the plan assumes a public `npx -y github:tellyworth/mpp-remote#<sha>` is installable for end users.

- [ ] **Step 3: Note the SHA in scratch state**

Keep the SHA at hand for Tasks 4 and 8 (the wrapper script and the README). No commit yet — nothing has been written.

---

## Task 2: Identify staging chain and USDC asset

**Files:** none (research output captured in Task 9 README)

The README needs to tell users which chain to send USDC on. The user's `screenshotter` project already wires up x402 against Cloudup staging, so the answer is in that codebase.

- [ ] **Step 1: Inspect the screenshotter x402 wiring for chain ID**

Read `/Users/bongnam/dev/screenshotter/Sources/ScreenshotterCore/Payment/X402.swift` and `/Users/bongnam/dev/screenshotter/Sources/Screenshotter/Funding/FundingPanel.swift`. Look for: chain ID, asset address, network name, faucet links.

- [ ] **Step 2: Cross-reference with an actual x402 challenge from staging**

If chain info is not obvious from screenshotter code, query the staging endpoint directly:
```bash
curl -s https://api.stage-cloudup.com/mcp/public -X POST \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | head -200
```

Then attempt a `quick_upload` to surface the x402 challenge. The challenge JSON contains `accepts: [{network, asset, ...}]` — that's authoritative.

- [ ] **Step 3: Note chain name, USDC contract address, and faucet info**

Keep these values for the README in Task 8. If the staging chain uses testnet USDC, note where users can get test USDC (faucet URL). No commit yet.

---

## Task 3: Scaffold plugin directory layout

**Files:**
- Create: `~/dev/cloudup-plugin/.claude-plugin/` (directory)
- Create: `~/dev/cloudup-plugin/scripts/` (directory)
- Create: `~/dev/cloudup-plugin/skills/uploading-to-cloudup/` (directory)
- Create: `~/dev/cloudup-plugin/commands/` (directory)

- [ ] **Step 1: Create the directory tree**

Run:
```bash
cd ~/dev/cloudup-plugin
mkdir -p .claude-plugin scripts skills/uploading-to-cloudup commands
```

- [ ] **Step 2: Verify**

Run:
```bash
cd ~/dev/cloudup-plugin && find . -type d -not -path './.git*' | sort
```

Expected output:
```
.
./.claude-plugin
./commands
./docs
./docs/superpowers
./docs/superpowers/plans
./docs/superpowers/specs
./scripts
./skills
./skills/uploading-to-cloudup
```

- [ ] **Step 3: No commit yet** — directories without files don't track in git. Tasks 4–9 will populate and commit.

---

## Task 4: Write the MCP wrapper script

**Files:**
- Create: `~/dev/cloudup-plugin/scripts/cloudup-server.sh`

The wrapper translates user-friendly env vars to mpp-remote's expected ones and execs `npx`. Using a script (instead of declaring env in `.mcp.json`) avoids depending on JSON env-var expansion semantics that may or may not be supported in plugin manifests.

- [ ] **Step 1: Write the script**

Replace `<MPP_REMOTE_SHA>` with the SHA from Task 1.

File contents:
```bash
#!/usr/bin/env bash
# Launches the mpp-remote MCP server pointed at Cloudup with payment env mapped
# from user-friendly CLOUDUP_* variables.

set -euo pipefail

: "${CLOUDUP_WALLET_KEY:?CLOUDUP_WALLET_KEY is not set. See the plugin README for setup.}"

exec env \
  MPP_WALLET_PRIVATE_KEY="${CLOUDUP_WALLET_KEY}" \
  MPP_MAX_AMOUNT_USD="${CLOUDUP_MAX_USD:-0.10}" \
  npx -y "https://github.com/tellyworth/mpp-remote/archive/<MPP_REMOTE_SHA>.tar.gz" \
  "${CLOUDUP_MCP_URL:-https://api.stage-cloudup.com/mcp/public}"
```

> **Why tarball URL, not `github:owner/repo#sha`:** npm v10.x ships a regression where `github:` and `git+https://` package specs that include a `#<sha>` ref fail with `GitFetcher requires an Arborist constructor to pack a tarball`. The archive-tarball URL bypasses npm's git fetcher entirely and still pins to the exact commit. Verified on node v22.20.0 / npm 10.9.3.

- [ ] **Step 2: Make it executable**

Run:
```bash
chmod +x ~/dev/cloudup-plugin/scripts/cloudup-server.sh
```

- [ ] **Step 3: Smoke-test the script outside Claude Code**

Run (substitute a real test wallet key):
```bash
CLOUDUP_WALLET_KEY=0xabc... ~/dev/cloudup-plugin/scripts/cloudup-server.sh --help 2>&1 | head -20
```

Expected: either mpp-remote prints help/usage, or it starts and waits on stdin (it's a stdio MCP server — Ctrl-C is fine). What you want to confirm is that `npx` resolved the package and the script didn't die before launching it. If it dies with "CLOUDUP_WALLET_KEY is not set", you forgot to set the env var.

If it dies for a different reason (npx couldn't resolve the SHA, the SHA points at a broken commit), bump to a SHA that works — possibly the immediately prior commit on main.

- [ ] **Step 4: Commit**

```bash
cd ~/dev/cloudup-plugin
git add scripts/cloudup-server.sh
git commit -m "Add cloudup-server.sh wrapper that maps user env to mpp-remote"
```

---

## Task 5: Write `.mcp.json`

**Files:**
- Create: `~/dev/cloudup-plugin/.mcp.json`

This declares the `cloudup` MCP server. The `command` references the wrapper script via `${CLAUDE_PLUGIN_ROOT}`, which Claude Code expands to the plugin's installed directory.

- [ ] **Step 1: Write the file**

```json
{
  "mcpServers": {
    "cloudup": {
      "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cloudup-server.sh"
    }
  }
}
```

- [ ] **Step 2: Validate JSON**

Run:
```bash
python3 -c "import json; json.load(open('/Users/bongnam/dev/cloudup-plugin/.mcp.json'))" && echo OK
```

Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
cd ~/dev/cloudup-plugin
git add .mcp.json
git commit -m "Declare cloudup MCP server in plugin .mcp.json"
```

---

## Task 6: Write plugin and marketplace manifests

**Files:**
- Create: `~/dev/cloudup-plugin/.claude-plugin/plugin.json`
- Create: `~/dev/cloudup-plugin/.claude-plugin/marketplace.json`

Plugin metadata follows the schema used by `claude-plugins-official/superpowers`. The marketplace manifest in the same repo lets users install with `claude plugin install <repo-url>` directly.

- [ ] **Step 1: Write `plugin.json`**

```json
{
  "name": "cloudup",
  "description": "Upload images to Cloudup via x402 micropayments. Agents can capture screenshots (e.g. Playwright) and embed shareable URLs in PR comments, issues, and chat.",
  "version": "0.1.0",
  "author": {
    "name": "Steve Dufresne",
    "email": "steve.dufresne@a8c.com"
  },
  "keywords": [
    "cloudup",
    "x402",
    "screenshots",
    "mcp",
    "upload"
  ]
}
```

- [ ] **Step 2: Write `marketplace.json`**

```json
{
  "name": "cloudup-plugin",
  "description": "Cloudup x402 upload plugin for Claude Code",
  "owner": {
    "name": "Steve Dufresne",
    "email": "steve.dufresne@a8c.com"
  },
  "plugins": [
    {
      "name": "cloudup",
      "description": "Upload images to Cloudup via x402 micropayments",
      "version": "0.1.0",
      "source": "./",
      "author": {
        "name": "Steve Dufresne",
        "email": "steve.dufresne@a8c.com"
      }
    }
  ]
}
```

- [ ] **Step 3: Validate JSON**

Run:
```bash
python3 -c "import json; json.load(open('/Users/bongnam/dev/cloudup-plugin/.claude-plugin/plugin.json')); json.load(open('/Users/bongnam/dev/cloudup-plugin/.claude-plugin/marketplace.json'))" && echo OK
```

Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
cd ~/dev/cloudup-plugin
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "Add plugin.json and marketplace.json manifests"
```

---

## Task 7: Write the `uploading-to-cloudup` skill

**Files:**
- Create: `~/dev/cloudup-plugin/skills/uploading-to-cloudup/SKILL.md`

The skill is the load-bearing piece: without it, the agent has no idea to reach for the upload tool. Scope is intentionally narrow per the spec.

- [ ] **Step 1: Write the skill**

````markdown
---
name: uploading-to-cloudup
description: Use when you have a screenshot or generated image on local disk that you need to share via URL — in a PR comment, GitHub issue reply, or chat response. Typically triggered after Playwright UI verification.
---

# Uploading images to Cloudup

You have access to an MCP server named `cloudup` that uploads local images to Cloudup and returns a public share URL. Use this when you have an image on disk and need to reference it in markdown that consumers will render — pull request comments, issue replies, chat responses.

## When to use

- You took a Playwright screenshot to verify a UI change and want to show the result in a PR comment
- The user asked you to share a screenshot
- You need to reference visual evidence (a generated chart, a diagram, a captured screen) in markdown that will be rendered by GitHub or another consumer

## When NOT to use

- The image is already hosted somewhere (the user already gave you a URL)
- The image may contain sensitive content (secrets, personal data, internal-only screens) — ask the user first
- You are just inspecting a file's metadata or dimensions — there is no need for a hosted URL

## How to use

1. Identify the absolute path to the local image file (e.g. `/tmp/screenshot.png`).
2. Call the upload tool from the `cloudup` MCP server. The exact tool name in your runtime is typically `mcp__cloudup__quick_upload` — discover it from the available tools list if naming differs.
3. The tool returns a JSON response containing the share URL.
4. Embed the URL in your markdown response as `![brief description](URL)`.
5. Tell the user the image was uploaded via x402 micropayment. They are paying for it from their configured wallet — this is expected and they should know.

## Costs and failures

Each upload is paid for by the user's wallet, configured via `CLOUDUP_WALLET_KEY`. The default cap is $0.10 per call (`CLOUDUP_MAX_USD`).

If the upload fails:
- **Missing key error** → point the user at the plugin README setup section
- **Cap exceeded** → tell the user; do not retry. They can raise `CLOUDUP_MAX_USD` if appropriate.
- **Insufficient balance** → tell the user to fund their wallet. Do not retry.
- **Network error** → one retry is fine; surface the error if it persists.

Never silently retry failed uploads — each retry potentially costs money.
````

- [ ] **Step 2: Commit**

```bash
cd ~/dev/cloudup-plugin
git add skills/uploading-to-cloudup/SKILL.md
git commit -m "Add uploading-to-cloudup skill teaching agents when to upload"
```

---

## Task 8: Write the `/cloudup` slash command

**Files:**
- Create: `~/dev/cloudup-plugin/commands/cloudup.md`

- [ ] **Step 1: Write the command file**

```markdown
---
name: cloudup
description: Upload a local image to Cloudup and print the shareable URL.
---

# /cloudup

Upload a local file to Cloudup via x402 micropayment and print the returned URL.

## Usage

```
/cloudup <path-to-image>
```

## Instructions

1. The user has invoked `/cloudup` with arguments: `$ARGUMENTS`
2. Treat `$ARGUMENTS` as a path to a local file. Resolve it to an absolute path if it isn't already.
3. Verify the file exists. If it does not, report the error and stop.
4. Call the `cloudup` MCP server's `quick_upload` tool with the resolved path.
5. On success, print the returned URL on its own line so the user can copy it. Include a one-line note that the upload was paid for via x402.
6. On failure, surface the error verbatim and do not retry silently. If the error is "missing key" or "insufficient balance", point the user at the plugin README.
```

- [ ] **Step 2: Commit**

```bash
cd ~/dev/cloudup-plugin
git add commands/cloudup.md
git commit -m "Add /cloudup slash command for explicit uploads"
```

---

## Task 9: Write the README

**Files:**
- Create: `~/dev/cloudup-plugin/README.md`

Substitute the chain name and faucet info from Task 2, and the SHA from Task 1.

- [ ] **Step 1: Write the README**

````markdown
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

Send USDC to that address on **<CHAIN_NAME_FROM_TASK_2>**. A small amount ($1–$5) is plenty for testing.

If the staging endpoint uses testnet USDC, a faucet is available at: <FAUCET_URL_FROM_TASK_2>

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
- **MCP server not starting** — Run `~/.claude/plugins/.../cloudup/scripts/cloudup-server.sh --help` manually with `CLOUDUP_WALLET_KEY` set to surface npx or network errors directly.

## Version

`0.1.0` — staging endpoint only. Prod endpoint, generated-wallet setup, and a balance command are planned for v0.2.

## License

MIT (or whatever the project ultimately picks — author's call).
````

- [ ] **Step 2: Replace placeholders**

Before committing, replace `<CHAIN_NAME_FROM_TASK_2>` and `<FAUCET_URL_FROM_TASK_2>` with the actual values determined in Task 2. If the staging endpoint uses mainnet (no faucet), delete the faucet line entirely.

- [ ] **Step 3: Commit**

```bash
cd ~/dev/cloudup-plugin
git add README.md
git commit -m "Add README with setup walkthrough and troubleshooting"
```

---

## Task 10: Manual end-to-end verification

**Files:** none

This is the only "test" in v1, per the spec. The plugin is config glue; we verify by installing and using it.

- [ ] **Step 1: Install the plugin locally in a Claude Code session**

In Claude Code, run:
```
/plugin install ~/dev/cloudup-plugin
```

Expected: plugin appears in the installed list. If it errors with a schema problem, the most likely cause is malformed JSON in `.claude-plugin/plugin.json` or `marketplace.json` — re-validate with `python3 -c "import json; json.load(open(...))"`.

- [ ] **Step 2: Confirm the MCP server starts**

Set `CLOUDUP_WALLET_KEY` in your environment (use a funded staging wallet). Open a new Claude Code session and run `/mcp`. Expect `cloudup` to appear as a connected server.

If it fails to connect:
- Check that `${CLAUDE_PLUGIN_ROOT}` expanded correctly — Claude Code's MCP log should show the resolved path.
- If `${CLAUDE_PLUGIN_ROOT}` did not expand, fall back to editing `.mcp.json` to use an absolute path during development, and file an upstream issue.

- [ ] **Step 3: Confirm the skill is discoverable**

Ask Claude: "What skills do you have available for working with images?"
Expected: it lists `uploading-to-cloudup` and summarizes its trigger conditions.

- [ ] **Step 4: Run `/cloudup` with a real file**

```
/cloudup /tmp/test.png
```

(Create `/tmp/test.png` first — any small image. `screencapture -i /tmp/test.png` on macOS works.)

Expected: the agent calls `quick_upload`, the wallet pays the x402 challenge, and the URL prints. Open the URL in a browser to confirm the image loaded.

- [ ] **Step 5: Run the natural-trigger path**

In a new session, ask: "Use Playwright to take a screenshot of https://example.com and embed it in a markdown response."

Expected: agent takes the screenshot, the skill triggers, the agent uploads via `cloudup`, the rendered markdown includes the resulting URL, and the agent notes that an x402 payment was made.

- [ ] **Step 6: Sanity-check failure surfaces**

Unset `CLOUDUP_WALLET_KEY` (or rename it to break the value). Run `/cloudup /tmp/test.png` again.

Expected: clear error pointing the user at the README setup section. The error must not be a cryptic shell-script failure.

- [ ] **Step 7: Commit any small fixes that surfaced during verification**

```bash
cd ~/dev/cloudup-plugin
git add -A
git status
# only commit if there are fixes; an empty diff means nothing to do
git commit -m "Polish from end-to-end verification"  # if applicable
```

---

## Done

When all tasks pass:
- Plugin installs cleanly
- MCP server connects with a configured wallet
- `/cloudup` works on an explicit path
- Skill triggers naturally when the agent has a screenshot to share
- Failure modes surface clearly

Ready to publish the repo and try it on a real PR. v0.2 work (generated wallet, balance command, prod endpoint) is out of scope for this plan.
