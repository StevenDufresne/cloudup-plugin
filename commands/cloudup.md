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
