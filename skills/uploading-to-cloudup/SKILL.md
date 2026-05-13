---
name: uploading-to-cloudup
description: Use when you have a screenshot or generated image on local disk that you need to share via URL — in a PR comment, GitHub issue reply, or chat response. Typically triggered after Playwright UI verification.
---

# Uploading images to Cloudup

You have access to a Cloudup MCP server that uploads local images and returns a public share URL. Use this when you have an image on disk and need to reference it in markdown that consumers will render — pull request comments, issue replies, chat responses.

The server is registered under the plugin-namespaced name `plugin:cloudup:cloudup` (Claude Code prefixes plugin-installed MCP servers with `plugin:<plugin-name>:`). When tooling asks for a `server` argument (e.g. `ListMcpResourcesTool`), pass that full name, not the bare `cloudup`.

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
2. Call the upload tool from the `plugin:cloudup:cloudup` MCP server. The runtime exposes tools using the namespace-normalized form: typically `mcp__plugin_cloudup_cloudup__upload_image` (colons replaced with underscores). If that exact name isn't surfaced, discover the right one from the available tools list — look for an `upload_image` or `quick_upload` tool under the cloudup-prefixed server. For non-image files, fall back to `quick_upload` on the same server.
3. The tool returns a JSON response containing `direct_url` (the hotlink), `markdown` (ready-to-paste GH-flavored markdown), `content_type`, `size_bytes`, `sku`, and `expires_at`.
4. Paste the `markdown` field verbatim into your response. If you want custom alt text, pass an `alt` argument on the call (it's stripped of `[`/`]` and capped at 200 chars); otherwise the alt is derived from the filename stem.
5. Tell the user the image was uploaded via x402 micropayment. They are paying for it from their configured wallet — this is expected and they should know. Mention the `expires_at`: the anonymous hotlink SKU (`hotlink-90d`) retains files for 90 days, after which the embed will turn into a broken-image icon in GitHub with no in-band explanation.

## Costs and failures

Each upload is paid for by the user's wallet, provisioned via `/cloudup-setup` (stored in macOS Keychain) or as a back-compat fallback the `CLOUDUP_WALLET_KEY` env var. The default cap is $0.10 per call (`CLOUDUP_MAX_USD`).

If the upload fails:
- **Cloudup MCP server not connected / tool not available at all** → almost always means no wallet key is provisioned yet. Tell the user to run `/cloudup-setup` (or set `CLOUDUP_WALLET_KEY` for the older path) and restart Claude Code.
- **Missing key error returned from the tool** → tell the user to run `/cloudup-setup`.
- **Cap exceeded** → tell the user; do not retry. They can raise `CLOUDUP_MAX_USD` if appropriate.
- **Insufficient balance** → tell the user to fund their wallet. Do not retry.
- **Network error** → one retry is fine; surface the error if it persists.

Never silently retry failed uploads — each retry potentially costs money.
