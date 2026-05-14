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

The server exposes two upload paths. **Pick by file size, not by reflex.**

### Path A — `upload_image` / `quick_upload` (inline base64)

Use when the file is small enough that you can read it without hitting your tooling's read limits. As a rule of thumb in Claude Code: under ~60 KB binary (~80 KB base64) is safely Read-able. Above that, switch to Path B.

1. Identify the absolute path to the local image file (e.g. `/tmp/screenshot.png`).
2. Call the upload tool from the `plugin:cloudup:cloudup` MCP server. The runtime exposes tools using the namespace-normalized form: typically `mcp__plugin_cloudup_cloudup__upload_image` (colons replaced with underscores). If that exact name isn't surfaced, discover the right one from the available tools list — look for an `upload_image` or `quick_upload` tool under the cloudup-prefixed server. For non-image files, use `quick_upload` on the same server.
3. The tool returns a JSON response containing `direct_url` (the hotlink), `markdown` (ready-to-paste GH-flavored markdown), `content_type`, `size_bytes`, `sku`, and `expires_at`.

### Path B — `begin_upload` + S3 PUT + `complete_upload` (presigned S3)

**Use this for anything Path A can't swallow whole.** Critically: **never degrade the image to fit Path A** — don't compress, downscale, or convert to lossy JPEG just to squeeze under the Read limit. The bytes never pass through your context on Path B, so the Read limit doesn't apply.

1. `stat -f%z <path>` (macOS) or `stat -c%s <path>` (Linux) to get the exact byte size.
2. Call `begin_upload` with `filename`, `mime`, `size_bytes`. It returns `s3_url`, `upload_id`, and `put_example` (a curl one-liner). Note: this SKU is more expensive than `upload_image` (typically $0.20 vs $0.10) — the plugin's default `CLOUDUP_MAX_USD` of `$0.20` covers it, but if you've lowered the cap or are uploading something charged higher than $0.20 the call will fail with `mpp-remote: charge … exceeds MPP_MAX_AMOUNT_USD=…`.
3. PUT the raw file bytes to `s3_url` from the shell — `curl -X PUT --data-binary @<path> -H "Content-Type: <mime>" "<s3_url>"`. The bytes go straight from disk to S3, never through your context.
4. Call `complete_upload` with the `upload_id` returned in step 2. It returns the same response shape as Path A (`direct_url`, `markdown`, etc.).

If the PUT fails or you stall past the presign TTL, call `begin_upload` again — don't try to reuse the expired URL.

### Both paths

- Paste the `markdown` field verbatim into your response. To customize alt text on Path A, pass an `alt` argument (stripped of `[`/`]`, capped at 200 chars); otherwise it's derived from the filename stem. Path B doesn't accept an `alt` argument — edit the returned markdown if you need different alt text.
- Tell the user the image was uploaded via x402 micropayment. They are paying for it from their configured wallet — this is expected and they should know. Mention the `expires_at`: the anonymous hotlink SKU (`hotlink-90d`) retains files for 90 days, after which the embed will turn into a broken-image icon in GitHub with no in-band explanation.

## Costs and failures

Each upload is paid for by the user's wallet, provisioned via `/cloudup-setup` (stored in macOS Keychain) or as a back-compat fallback the `CLOUDUP_WALLET_KEY` env var. The default cap is $0.20 per call (`CLOUDUP_MAX_USD`) — covers both Path A (`upload_image` / `quick_upload`, ~$0.10) and Path B (`begin_upload`, ~$0.20).

If the upload fails:
- **Cloudup MCP server not connected / tool not available at all** → almost always means no wallet key is provisioned yet. Tell the user to run `/cloudup-setup` (or set `CLOUDUP_WALLET_KEY` for the older path) and restart Claude Code.
- **Missing key error returned from the tool** → tell the user to run `/cloudup-setup`.
- **Cap exceeded** → tell the user; do not retry. They can raise `CLOUDUP_MAX_USD` if appropriate.
- **Insufficient balance** → tell the user to fund their wallet. Do not retry.
- **Network error** → one retry is fine; surface the error if it persists.

Never silently retry failed uploads — each retry potentially costs money.
