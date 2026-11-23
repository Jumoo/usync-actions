#!/usr/bin/env bash
# Runs `uSync files-verify` for the verify action. Always exits 0 so the SARIF upload
# can still run; the action fails in a later step using the exit-code output.
set -uo pipefail

is_true() { [ "${1:-false}" = "true" ]; }

cli="$USYNC_CLI"
args=(files-verify)
[ -n "${INPUT_FOLDER:-}" ] && args+=(--folder "$INPUT_FOLDER")
is_true "${INPUT_CONTENT:-}" && args+=(--content)
is_true "${INPUT_WARNINGS_AS_ERRORS:-}" && args+=(--warnings-as-errors)
[ -n "${INPUT_CHANGED_SINCE:-}" ] && args+=(--changed-since "$INPUT_CHANGED_SINCE")
[ -n "${INPUT_PUBLISH_FOLDER:-}" ] && args+=(--publish-folder "$INPUT_PUBLISH_FOLDER")

summary=()
is_true "${INPUT_SUMMARY:-}" && summary=(--summary)

"$cli" "${args[@]}" ${summary[@]+"${summary[@]}"} --format github
code=$?
echo "exit-code=$code" >> "$GITHUB_OUTPUT"

if is_true "${INPUT_SARIF:-}"; then
  "$cli" "${args[@]}" --format sarif --output "$INPUT_SARIF_FILE" >/dev/null
  if [ -f "$INPUT_SARIF_FILE" ]; then
    echo "sarif-file=$INPUT_SARIF_FILE" >> "$GITHUB_OUTPUT"
  else
    echo "::warning::uSync files-verify did not write $INPUT_SARIF_FILE"
  fi
fi

exit 0
