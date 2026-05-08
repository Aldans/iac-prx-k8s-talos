#!/usr/bin/env bash
# Stop hook: when Claude finishes answering, emit a soft reminder if the session
# touched ≥3 .tf/.tftpl files. Non-blocking, does not run any commands.

set -uo pipefail

INPUT=$(cat)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  exit 0
fi

# Count Edit/Write tool calls made on .tf/.tftpl files in the current transcript.
# Transcript is JSONL, one event per line. Tool input lives at .message.content[].input.file_path.
TF_EDIT_COUNT=$(jq -s '
  [
    .[]
    | select(.message.content?)
    | .message.content[]?
    | select(.type == "tool_use")
    | select(.name == "Edit" or .name == "Write" or .name == "MultiEdit")
    | .input.file_path // .input.filePath // empty
    | select(test("\\.tf$|\\.tftpl$"))
  ]
  | length
' "$TRANSCRIPT" 2>/dev/null || echo 0)

# Safety: if jq returned empty or a non-number, just exit.
if ! [[ "$TF_EDIT_COUNT" =~ ^[0-9]+$ ]] || [ "$TF_EDIT_COUNT" -lt 3 ]; then
  exit 0
fi

jq -n --argjson count "$TF_EDIT_COUNT" '{
  "systemMessage": ("🔁 This session edited " + ($count | tostring) + " .tf/.tftpl files. Before apply run /test (static + plan) or /cycle (audit→fix→test). Reminder only — nothing runs automatically.")
}'

exit 0
