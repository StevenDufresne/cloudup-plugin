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
2. Call the upload tool from the `cloudup` MCP server. The exact tool name in your runtime is typically `mcp__cloudup__upload_image` — discover it from the available tools list if naming differs. For non-image files, fall back to `mcp__cloudup__quick_upload`.
3. The tool returns a JSON response containing `direct_url` (the hotlink), `markdown` (ready-to-paste GH-flavored markdown), `content_type`, `size_bytes`, `sku`, and `expires_at`.
4. Paste the `markdown` field verbatim into your response. If you want custom alt text, pass an `alt` argument on the call (it's stripped of `[`/`]` and capped at 200 chars); otherwise the alt is derived from the filename stem.
5. Tell the user the image was uploaded via x402 micropayment. They are paying for it from their configured wallet — this is expected and they should know. Mention the `expires_at`: the anonymous hotlink SKU (`hotlink-90d`) retains files for 90 days, after which the embed will turn into a broken-image icon in GitHub with no in-band explanation.

## Costs and failures

Each upload is paid for by the user's wallet, configured via `CLOUDUP_WALLET_KEY`. The default cap is $0.10 per call (`CLOUDUP_MAX_USD`).

If the upload fails:
- **`cloudup` MCP server not connected / tool not available at all** → almost always means `CLOUDUP_WALLET_KEY` is unset (the wrapper script refuses to start the server without it). Point the user at the plugin README setup section.
- **Missing key error returned from the tool** → point the user at the plugin README setup section.
- **Cap exceeded** → tell the user; do not retry. They can raise `CLOUDUP_MAX_USD` if appropriate.
- **Insufficient balance** → tell the user to fund their wallet. Do not retry.
- **Network error** → one retry is fine; surface the error if it persists.

Never silently retry failed uploads — each retry potentially costs money.
