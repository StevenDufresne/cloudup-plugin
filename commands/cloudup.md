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
4. Call the `cloudup` MCP server's `upload_image` tool with the file's bytes (base64-encoded). The tool sniffs the MIME server-side and rejects non-image content; for non-image files, use `quick_upload` instead.
5. On success, print the returned `direct_url` on its own line so the user can copy it, then print the `markdown` field (ready to paste into a PR/issue body). Include a one-line note that the upload was paid for via x402 and that the anonymous hotlink expires on the date in `expires_at`.
6. On failure, surface the error verbatim and do not retry silently. Specifically:
   - "missing key" or "insufficient balance" → point the user at the plugin README.
   - "cap exceeded" → report and stop; do not retry. The user can raise `CLOUDUP_MAX_USD`.
   - "only accepts image content" → the file isn't a recognised image type; offer to retry with `quick_upload`.
   - Network errors → one retry is acceptable; surface the failure if it persists.
