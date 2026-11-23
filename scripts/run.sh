#!/usr/bin/env bash
# Runs a connected uSync.Cli command for the run action. Server and credentials arrive as
# USYNC_SERVER / USYNC_CLIENT_ID / USYNC_CLIENT_SECRET and never go on the command line.
set -uo pipefail

for name in USYNC_SERVER USYNC_CLIENT_ID USYNC_CLIENT_SECRET; do
  # an empty variable would hide a value from appsettings.json
  [ -z "${!name:-}" ] && unset "$name"
done
[ -n "${USYNC_CLIENT_SECRET:-}" ] && echo "::add-mask::$USYNC_CLIENT_SECRET"

if [ -z "${INPUT_COMMAND:-}" ]; then
  echo "::error::The 'command' input is required (for example usync-ping or usync-import)"
  exit 2
fi

# args: one argument per line, or (single line) split on whitespace.
extra=()
if [[ "${INPUT_ARGS:-}" == *$'\n'* ]]; then
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [ -n "$line" ] && extra+=("$line")
  done <<< "$INPUT_ARGS"
elif [ -n "${INPUT_ARGS:-}" ]; then
  read -r -a extra <<< "$INPUT_ARGS"
fi

"$USYNC_CLI" "$INPUT_COMMAND" ${extra[@]+"${extra[@]}"}
code=$?
echo "exit-code=$code" >> "$GITHUB_OUTPUT"
exit "$code"
