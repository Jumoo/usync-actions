#!/usr/bin/env bash
# Installs uSync.Cli for the setup, verify and run actions.
#   setup.sh runtime   is the .NET runtime the tool needs already here?
#   setup.sh resolve   work out the version to install and where to put it
#   setup.sh install   install the tool (unless the cache restored it) and put it on PATH
# Inputs come in as INPUT_* environment variables, never as ${{ }} in the script.
set -euo pipefail

package_id="uSync.Cli"
commands=(uSyncCli uSync)   # uSyncCli is the tool command; uSync is kept as a fallback

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

xml_escape() {
  local s="$1"
  s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; s="${s//\"/&quot;}"
  printf '%s' "$s"
}

# NuGet reads a relative source in a nuget.config as relative to the config file, which
# lives in a temp folder, so turn a relative folder into an absolute one first.
absolute_source() {
  local s="$1" base
  case "$s" in
    *://* | /* | [A-Za-z]:* | '\'*) printf '%s' "$s"; return ;;
  esac
  base="$(pwd -W 2>/dev/null || pwd)"   # pwd -W gives C:/... under Git Bash on Windows
  printf '%s/%s' "$base" "$s"
}

write_nuget_config() {
  local dir file
  dir="$(mktemp -d)"
  file="$dir/nuget.config"
  cat > "$file" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="usync-extra" value="$(xml_escape "$1")" />
  </packageSources>
  <packageSourceMapping>
    <clear />
  </packageSourceMapping>
</configuration>
EOF
  printf '%s' "$file"
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
        # --add-source fails when the machine or repo uses package source mapping,
        # so install from a config of our own: nuget.org plus the extra source, no mapping.
        args+=(--configfile "$(write_nuget_config "$(absolute_source "$INPUT_SOURCE")")")
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
