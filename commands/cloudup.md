---
name: cloudup
description: Upload an image to Cloudup and print the shareable URL. Works with a file path, or with an image already pasted into the conversation.
---

# /cloudup

Upload an image to Cloudup via x402 micropayment and print the returned URL plus ready-to-paste markdown.

## Usage

```
/cloudup <path-to-image>
/cloudup                    # upload an image already pasted into the conversation
```

## Instructions

1. The user has invoked `/cloudup` with arguments: `$ARGUMENTS`.
2. Decide which input source to upload:
   - **`$ARGUMENTS` is non-empty** → treat it as a path to a local file. Resolve it to an absolute path if it isn't already, and verify the file exists. If it doesn't, report the error and stop.
   - **`$ARGUMENTS` is empty** → look for an image in the current conversation context: either an MCP `image` content block (e.g. from a Playwright screenshot tool, the user pasting a screenshot into chat, or a previous tool response) or a `data:image/...;base64,...` URL. If none is present, report that no image was supplied and stop.
3. Invoke the `cloudup:uploading-to-cloudup` skill to perform the upload, passing it whichever input source was identified in step 2 (a file path, an MCP image block, or a data URL). The skill is the single source of truth for which upload path to use, how to handle errors, and how to present the result.
