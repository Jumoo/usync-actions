# uSync actions

Build and deploy pipeline steps for Umbraco sites that use [uSync](https://jumoo.co.uk/usync).

- **verify** checks the uSync files in your repo on every pull request: merge conflict markers, invalid XML, two files with the same key, two items with the same alias, delete markers that clash with live items. No site, database or secrets needed.
- **run** talks to a running site after a deploy: wait for it to come up, run an import, get a report of what an import would change, rebuild caches, run health checks.
- **setup** installs the tool, if you want to call it yourself.

All three are thin wrappers around the [`uSync.Cli`](https://github.com/Jumoo/uSync.CommandLine) dotnet tool, so the same checks run on your machine (`uSyncCli files-verify`) and on [Azure DevOps, GitLab, Bitbucket, TeamCity and Octopus](docs/other-platforms.md).

## Quick start

Check uSync files on pull requests:

```yaml
# .github/workflows/usync.yml
name: uSync checks
on: pull_request

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: Jumoo/usync-actions/verify@v1
        with:
          working-directory: src/MySite   # where appsettings.json is
```

Import after a deploy:

```yaml
      # ... deploy the site ...
      - uses: Jumoo/usync-actions/run@v1
        with:
          command: usync-ping          # wait for the site to restart
          args: --timeout 300
          server: ${{ vars.SITE_URL }}
          client-id: ${{ secrets.USYNC_CLIENT_ID }}
          client-secret: ${{ secrets.USYNC_CLIENT_SECRET }}

      - uses: Jumoo/usync-actions/run@v1
        with:
          command: usync-import
          server: ${{ vars.SITE_URL }}
          client-id: ${{ secrets.USYNC_CLIENT_ID }}
          client-secret: ${{ secrets.USYNC_CLIENT_SECRET }}
```

More in [`examples/`](examples):

| Example | What it shows |
|---|---|
| [pr-checks.yml](examples/pr-checks.yml) | Checks on pull requests, only reporting files the PR changed, with a change summary and SARIF upload |
| [deploy-azure-webapp.yml](examples/deploy-azure-webapp.yml) | Publish, check the uSync folder made it into the output, deploy to an Azure Web App, report, import |
| [deploy-iis.yml](examples/deploy-iis.yml) | Checks on a hosted runner, then Web Deploy to IIS from a self-hosted runner, import, health check |
| [umbraco-cloud.yml](examples/umbraco-cloud.yml) | Checks before pushing to Umbraco Cloud (Cloud imports on the site, so only the file checks apply) |
| [deploy-callback.yml](examples/deploy-callback.yml) + [deploy-result.yml](examples/deploy-result.yml) | Deploy and stop; the site tells GitHub when it's up and the import runs then, so no runner waits for the restart. Setup in [docs/deploy-callback.md](docs/deploy-callback.md) |

## verify

`Jumoo/usync-actions/verify@v1` (also published at the repo root as `Jumoo/usync-actions@v1`, which is the one listed on the Marketplace).

Runs `uSyncCli files-verify`. Problems show as annotations on the pull request's changed files. The step fails if it finds errors.

What it checks:

| Errors (fail the build) | Warnings (reported; fail with `warnings-as-errors`) |
|---|---|
| Merge conflict markers in any file, including inside CDATA values that still parse as XML | References to keys no file defines (compositions, data types, templates, allowed children) |
| `.config` files that aren't valid XML | Files exported by an older uSync than the site uses |
| Two files of the same type with the same `Key` | Unknown folders, files that aren't `.config` |
| Two items of the same type with the same `Alias` and different keys | Content with no matching content type file |
| A delete marker and a live item with the same `Key` | |

Content, Media and Blueprints folders are skipped unless you set `content: true`.

### Inputs

| Input | Default | Description |
|---|---|---|
| `working-directory` | `.` | Folder to run in: your site root, where `appsettings.json` is. |
| `folder` | | uSync folder. Default: `uSync:Settings:RootFolder` from `appsettings.json`, else the highest `uSync/v{n}`. |
| `content` | `false` | Also check Content, Media and Blueprints. |
| `warnings-as-errors` | `false` | Fail on warnings too. |
| `changed-since` | | Git ref, e.g. `origin/${{ github.base_ref }}`. Only problems in files changed since then are reported; everything is still loaded, so a new file that clashes with an old one is caught. Check out with `fetch-depth: 0`. |
| `summary` | `false` | Write a table of the doc types, data types and content this branch changes to the job summary. Use with `changed-since`. |
| `publish-folder` | | A publish output folder. Checks it contains the uSync folder with the same files. |
| `sarif` | `false` | Also write a SARIF report. |
| `sarif-file` | `usync.sarif` | Where to write it, relative to `working-directory`. |
| `upload-sarif` | `true` | Upload the SARIF report to code scanning (when `sarif` is on). The job needs `permissions: security-events: write`. |
| `version` | `latest` | uSync.Cli version. `latest` is the newest stable release on nuget.org. |
| `prerelease` | `false` | Allow prereleases when `version` is `latest`. |
| `dotnet-version` | `10.0.x` | .NET SDK to install if the .NET 10 runtime isn't already on the runner. |
| `source` | | Extra NuGet source (URL or folder) to install the tool from. |

### Outputs

| Output | Description |
|---|---|
| `exit-code` | `0` clean, `1` problems found, `2` the tool couldn't run (folder not found, bad arguments). |
| `sarif-file` | Path to the SARIF report, if written. |
| `version` | uSync.Cli version used. |

To act on the result instead of failing, use `continue-on-error: true` and read `steps.<id>.outputs.exit-code`.

## run

`Jumoo/usync-actions/run@v1`

Runs any connected uSync.Cli command against a site, over the Umbraco Management API. Commands include `usync-ping`, `usync-import`, `usync-export`, `usync-report`, `cache-rebuild`, `models-rebuild`, `indexer-rebuild` and `healthcheck-group-check`. Run `uSyncCli --help` for the full list.

The server and credentials go to the tool as the environment variables `USYNC_SERVER`, `USYNC_CLIENT_ID` and `USYNC_CLIENT_SECRET`, never on the command line, so they stay out of the logs.

### Inputs

| Input | Default | Description |
|---|---|---|
| `command` | (required) | The command, e.g. `usync-import`. |
| `args` | | Extra arguments. On one line they're split on spaces (`--timeout 300`); for values with spaces, put one argument per line. Don't put secrets here. |
| `server` | | Site URL. |
| `client-id` | | API user client id. Use a secret. |
| `client-secret` | | API user client secret. Use a secret. |
| `working-directory` | `.` | Folder to run in. An `appsettings.json` there is read for settings the inputs don't give. |
| `version`, `prerelease`, `dotnet-version`, `source` | | As for verify. |

### Outputs

| Output | Description |
|---|---|
| `exit-code` | The command's exit code. |
| `version` | uSync.Cli version used. |

Useful exit codes: `usync-ping` exits `1` if the site doesn't answer within `--timeout` seconds (default 300). `healthcheck-group-check` exits `1` when any check reports an error. `usync-import` exits non-zero if a handler or item fails. `usync-import` and `usync-report` add a table of changes to the job summary.

### API user

Connected commands log in as an Umbraco API user with a client id and secret. To set one up, follow [Create an API user](https://github.com/Jumoo/uSync.CommandLine#create-an-api-user) in the uSync.CommandLine readme, then store the id and secret as repository or environment secrets (`USYNC_CLIENT_ID`, `USYNC_CLIENT_SECRET`).

## setup

`Jumoo/usync-actions/setup@v1`

Installs uSync.Cli and puts it on `PATH`, for when you want to call the tool yourself.

```yaml
- uses: Jumoo/usync-actions/setup@v1
- run: uSyncCli files-verify --format junit --output usync.xml
```

| Input | Default | Description |
|---|---|---|
| `version` | `latest` | uSync.Cli version. |
| `prerelease` | `false` | Allow prereleases when `version` is `latest`. |
| `dotnet-version` | `10.0.x` | .NET SDK to install if the .NET 10 runtime is missing. |
| `source` | | Extra NuGet source. |

| Output | Description |
|---|---|
| `version` | The version installed. |
| `command` | Full path to the tool. |

It skips `actions/setup-dotnet` when the runner already has the .NET 10 runtime (GitHub's hosted images do), and caches the tool by version, so after the first run it costs a second or two. It works on Linux, Windows and macOS runners, hosted or self-hosted.

## Other platforms

- Azure DevOps: step templates in [`azure-devops/templates`](azure-devops/templates)
- GitLab: CI/CD components in [`gitlab/templates`](gitlab/templates)
- Bitbucket, TeamCity, Octopus: script steps in [docs/other-platforms.md](docs/other-platforms.md)

## Versions

Pin to the major tag: `@v1`. It moves to each new `v1.x.y` release, so you get fixes and new inputs without changing your workflow. Anything that would break an existing workflow (a removed or renamed input, a changed default, a new required permission) goes into `v2`. Pin to a full version (`@v1.2.0`) or a commit SHA if you want nothing to change under you.

The actions version separately from uSync.Cli. By default they install the latest stable uSync.Cli; set `version` to pin the tool as well.

## Developing

The logic is in [`scripts/`](scripts); each `action.yml` passes its inputs to a script through environment variables (never `${{ }}` inside a script, which would allow script injection). `action.yml` and `verify/action.yml` must be identical; CI checks.

Tests run the actions against the folders in [`test/fixtures`](test/fixtures): one that must pass and several that must fail, one per check. `make-fixtures.py` regenerates them. To run the same checks locally against a uSync.Cli build in `.local-feed`:

```powershell
./test/run-local.ps1
```

## Credits

Matthew Hart's [actions-uSync-cli](https://github.com/mattou07/actions-uSync-cli) did this first, for the earlier uSync command line, and his use cases (post-deploy ping, import, cache rebuild, filling on-demand environments with uSync content) shaped the `run` action. Thanks Matt.

## License

MPL-2.0, the same as uSync.
