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

1. The user has invoked `/cloudup` with arguments: `$ARGUMENTS`.
2. Treat `$ARGUMENTS` as a path to a local file. Resolve it to an absolute path if it isn't already, and verify the file exists. If it does not, report the error and stop.
3. Invoke the `cloudup:uploading-to-cloudup` skill to perform the upload. That skill is the single source of truth for which upload path to use (inline `upload_image`/`quick_upload` for small files vs. `begin_upload` + S3 PUT + `complete_upload` for larger files), how to handle errors, and how to present the result.
