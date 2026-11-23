#!/usr/bin/env bash
# Installs uSync.Cli for the setup, verify and run actions.
#   setup.sh runtime   is the .NET runtime the tool needs already here?
#   setup.sh resolve   work out the version to install and where to put it
#   setup.sh install   install the tool (unless the cache restored it) and put it on PATH
# Inputs come in as INPUT_* environment variables, never as ${{ }} in the script.
set -euo pipefail

package_id="uSync.Cli"
commands=(uSync uSyncCli)   # uSync is the v1 contract; uSyncCli is the name older builds use

out() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }

find_command() {
  local dir="$1" name
  for name in "${commands[@]}"; do
    if [ -f "$dir/$name" ] || [ -f "$dir/$name.exe" ]; then
      echo "$dir/$name"
      return 0
    fi
  done
  return 1
}

case "${1:-}" in
  runtime)
    major="${INPUT_DOTNET_VERSION%%.*}"
    if command -v dotnet >/dev/null 2>&1 \
       && dotnet --list-runtimes 2>/dev/null | grep -q "^Microsoft.NETCore.App ${major}\."; then
      echo ".NET ${major} runtime found, skipping setup-dotnet"
      out needed false
    else
      echo ".NET ${major} runtime not found, installing SDK ${INPUT_DOTNET_VERSION}"
      out needed true
    fi
    ;;

  resolve)
    version="${INPUT_VERSION:-latest}"
    if [ "$version" = "latest" ]; then
      version=""
      # With an extra source (a local feed in tests, a private feed) we can't ask nuget.org,
      # so let dotnet pick and skip the cache.
      if [ -z "${INPUT_SOURCE:-}" ]; then
        index="$(curl -fsSL --retry 3 "https://api.nuget.org/v3-flatcontainer/usync.cli/index.json" || true)"
        list="$(printf '%s' "$index" | tr -d ' \r\n' | grep -o '"[0-9][^"]*"' | tr -d '"' || true)"
        if [ "${INPUT_PRERELEASE:-false}" != "true" ]; then
          list="$(printf '%s\n' "$list" | grep -v -- '-' || true)"
        fi
        # nuget.org lists versions oldest first
        version="$(printf '%s\n' "$list" | grep . | tail -n 1 || true)"
      fi
    fi

    if [ -n "$version" ] && [ -z "${INPUT_SOURCE:-}" ]; then
      tool_path="${RUNNER_TOOL_CACHE:-$RUNNER_TEMP}/usync-cli/$version"
      out cache true
    else
      # Unpinned or from an extra feed: install fresh into the job's temp folder.
      tool_path="$RUNNER_TEMP/usync-cli"
      out cache false
    fi
    echo "uSync.Cli version: ${version:-latest available}"
    out version "$version"
    out tool-path "$tool_path"
    ;;

  install)
    tool_path="$TOOL_PATH"
    if cli="$(find_command "$tool_path")"; then
      echo "uSync.Cli already in $tool_path"
    else
      args=(tool install "$package_id" --tool-path "$tool_path")
      if [ -n "${VERSION:-}" ]; then
        args+=(--version "$VERSION")
      elif [ "${INPUT_PRERELEASE:-false}" = "true" ]; then
        args+=(--prerelease)
      fi
      if [ -n "${INPUT_SOURCE:-}" ]; then
        args+=(--add-source "$INPUT_SOURCE")
      fi
      dotnet "${args[@]}"
      cli="$(find_command "$tool_path")" || {
        echo "::error::uSync.Cli installed but neither of '${commands[*]}' was found in $tool_path"
        exit 1
      }
    fi

    echo "$tool_path" >> "$GITHUB_PATH"
    installed="$(dotnet tool list --tool-path "$tool_path" | awk 'tolower($1)=="usync.cli" {print $2}')"
    echo "Using $cli ($installed)"
    out version "$installed"
    out command "$cli"
    ;;

  *)
    echo "usage: setup.sh runtime|resolve|install" >&2
    exit 2
    ;;
esac
