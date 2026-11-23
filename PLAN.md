# uSync pipeline actions: plan

Draft, 2026-11-23.

## What we're building

Steps people can drop into a build or deploy pipeline for an Umbraco site that has uSync files in it. They fall into two groups, and the split drives most of the decisions below.

1. **File checks.** Run against the checked-out repo. No site, no database, no secrets. These run on every pull request and fail the build before bad files reach a server.
2. **Site commands.** Talk to a running site over the Management API: wait for it to come up, run an import, rebuild caches, run health checks. These run after a deploy and need an API user's client id and secret.

## The main decision: .NET or not?

I think the logic should be .NET, as commands in uSync.Cli, with thin per-platform wrappers around it.

Reasons:

- Every pipeline that builds an Umbraco site already has the .NET SDK on it. Being "not .NET" saves nothing for our users.
- The site commands already exist in uSync.Cli (`usync-ping`, `usync-import`, `cache-rebuild`, `healthcheck-group-check`...). Rewriting them in TypeScript means keeping two Management API clients in step.
- A dotnet tool runs the same on GitHub, Azure DevOps, GitLab, Bitbucket, Octopus, TeamCity and a developer's own machine. A TypeScript action only runs on GitHub. With the logic in the tool, each platform wrapper is a few lines of YAML.
- Developers can run `uSyncCli files-verify` locally or in a pre-commit hook and get the same answer as CI.
- The checks are plain XML work (`System.Xml.Linq`). We don't need uSync.Core for them, which is good, because uSync.Core drags in Umbraco.Cms.Core.

The case for TypeScript was speed (no tool install) and a native GitHub feel. Installing a small dotnet tool takes a few seconds, and we can get the native feel by writing GitHub annotations from the tool.

`uSync.Cli` already separates connected commands (`ConnectedCommandBase`), so offline commands fit alongside them without a server or keys.

One thing to watch: the CLI targets `net10.0` only. GitHub's hosted images ship .NET 10, but the wrapper action should still call `actions/setup-dotnet` when the version isn't there, or the tool should set `RollForward=Major`.

## Part 1: file checks (`uSyncCli files-verify`)

New offline command in uSync.Cli:

```
uSyncCli files-verify [--folder uSync/v17] [--format text|github|sarif|junit] [--warnings-as-errors]
```

It finds the uSync folder itself (same discovery as the site: `uSync:Settings:RootFolder` in appsettings, falling back to `uSync/v{n}`).

### Checks

Errors (fail the build):

| Check | Why |
|---|---|
| Merge conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) in any file | Markers inside a CDATA block (block list JSON, RTE values) still parse as valid XML, so the existing health check misses them. Scan the raw text. |
| `.config` file isn't valid XML | Same as the "Invalid .config files" health check. |
| Two files of the same type share a `Key` | Same as the "Folder Clash check" health check. Usually a copy-paste or a bad merge. |
| Two items of the same type share an `Alias` with different `Key`s | The classic two-branch clash: two developers each create `article` on their own branch. Each file is fine alone; together the import fails or overwrites. |
| An `<Empty Change="Delete">` and a live item share a `Key` | uSync reports this at import time (`SyncHandlerRoot` duplicate check). Catch it at PR time instead. |

Warnings (report, optionally fail):

| Check | Why |
|---|---|
| Broken references: a composition, parent, data type, template or allowed child `Key` that no file in the folder defines | Often fine (the item exists in the target database), so a warning. Points at a missing file in the commit. |
| `usync.config` format version older than the uSync package in the site's `.csproj` | Files exported by an older uSync. |
| Unknown folder names, or files that aren't `.config` | Usually leftovers. |
| Content files with no matching content type file | Import will fail for those items. |

Later, maybe:

- `--changed-only` mode that only looks at files changed in the PR (`git diff --name-only origin/main...`), for very large content folders.
- A PR summary: which doc types, data types and content items this branch changes, written to `$GITHUB_STEP_SUMMARY` as a markdown table. Cheap to do once we parse everything anyway, and reviewers would use it.
- `files-verify --publish-folder ./publish`: check the publish output actually contains the uSync folder. Forgetting to copy it is a common deploy mistake, and the only symptom is that nothing imports.

### Shared code with the site

The clash and validity logic now lives in `SyncFolderIntegrityChecks` and `SyncFileService` inside uSync.BackOffice. Pull it into a small package with no Umbraco dependency (say `uSync.Files`) that both the health check and the CLI use. That stops them drifting apart. This can come second: write it in the CLI first, then move it.

### Output

- `text`: default, for local use.
- `github`: `::error file=uSync/v17/ContentTypes/article.config,line=1::Alias 'article' also used by article_1.config`. Shows inline on the PR diff. Pick this automatically when `GITHUB_ACTIONS=true`.
- `sarif`: for GitHub code scanning and Azure DevOps. Gives a persistent list instead of per-run logs.
- `junit`: Azure DevOps and GitLab both show JUnit results natively.
- Exit code 0 / 1 / 2 (ok / errors / tool failure).

## Part 2: site commands (existing uSync.Cli)

Mostly done already. Pipeline gaps worth filling:

- **`usync-report`**: a dry run that says what an import would change. Run it against staging before the deploy and post the result to the PR or step summary. uSync has the report endpoint; the CLI doesn't call it yet.
- **Step summary output**: `usync-import` and `usync-report` should write a markdown table to `$GITHUB_STEP_SUMMARY` when it's set.
- **Exit codes on health checks**: `healthcheck-group-check --group uSync` should exit non-zero on an error result, so a pipeline can run the folder clash check on the deployed site.
- **`usync-ping --timeout`**: check it has a timeout and a clear "site never came up" exit, because a post-deploy wait that hangs forever burns runner minutes.
- **Secrets from environment variables**: `USYNC_CLIENT_ID` / `USYNC_CLIENT_SECRET` / `USYNC_SERVER`, so the YAML never has keys on the command line, where they can end up in logs.

## Part 3: wrappers per platform

### GitHub (first)

Composite actions in this repo. No TypeScript, no `dist/` folder to rebuild:

```
usync-actions/
  setup/action.yml     installs uSync.Cli (version input, caches the tool)
  verify/action.yml    setup + files-verify, github format, optional SARIF upload
  run/action.yml       setup + any connected command (server, client-id, client-secret inputs)
  examples/
    pr-checks.yml
    deploy-azure-webapp.yml
    deploy-iis.yml
    umbraco-cloud.yml
```

Usage:

```yaml
- uses: Jumoo/usync-actions/verify@v1

# after deploy
- uses: Jumoo/usync-actions/run@v1
  with:
    command: usync-ping
    server: ${{ vars.SITE_URL }}
    client-id: ${{ secrets.USYNC_CLIENT_ID }}
    client-secret: ${{ secrets.USYNC_CLIENT_SECRET }}
- uses: Jumoo/usync-actions/run@v1
  with:
    command: usync-import
    ...
```

The Marketplace lists only one action per repo, and that action must be `action.yml` at the root. If listing matters, put `verify` at the root (it's the one most people will want) and keep the others as sub-paths, or split into `usync-verify-action` and `usync-cli-action`. I'd start with one repo and sub-paths, and only split once we know whether the listing brings people in.

### Others

Once the tool does the work, these are templates and docs:

- **Azure DevOps**: YAML templates (`template: usync/verify.yml@usync-actions`). A Marketplace task extension is possible later but needs a publisher account and a TypeScript task, so not for v1.
- **GitLab**: a CI/CD component (`include: component: gitlab.com/jumoo/usync/verify@1`).
- **Bitbucket, TeamCity, Octopus**: documented script steps. Octopus could get a community step template for the post-deploy import, since that is where most IIS deploys run.
- **Umbraco Cloud**: no post-deploy hook, and uSync imports on the site itself, so only the file checks apply. Run them on the PR before pushing to the Cloud repo. Worth an example, because it's a large audience.

## Prior art

Matthew Hart's [actions-uSync-cli](https://github.com/mattou07/actions-uSync-cli) (24 days in Umbraco, 2024) is a TypeScript `setup` + `invoke` pair around the CLI. It targets the old CLI (`uSync run <command>` with an HMAC key), not the v15+ Management API one with client id and secret, so it won't work with current sites as is. Worth contacting Matt: either he updates his and we point at it, or ours supersedes it with his blessing. His use cases (post-deploy ping, import, cache rebuild, on-demand environments filled with uSync content) match Part 2.

## Suggested order

1. `files-verify` in uSync.Cli with the five error checks and `text` + `github` output. Test on a deliberately broken branch (two branches each adding `article`, a conflicted block list value).
2. `setup` and `verify` composite actions plus the PR example workflow. Release as `v0` and use it on our own repos.
3. CLI fixes from Part 2 (env var secrets, ping timeout, health check exit codes), then the `run` action and deploy examples.
4. Warnings, SARIF and JUnit output, step summary.
5. `usync-report` and the PR change summary.
6. Azure DevOps and GitLab templates, Umbraco Cloud example.
7. Move shared check code into `uSync.Files` and point the health check at it.

## Decisions (2026-11-23)

- Actions are versioned on their own: `v1`.
- One tool: everything goes in `uSync.Cli`.
- Content checks are opt-in with `--content`. Without it, `Content`, `Media` and `Blueprints` folders are skipped.

## CLI interface (the contract between the CLI and the actions)

Both repos build against this. Change it here first if it has to change.

### `uSyncCli files-verify` (offline, no server or keys)

| Option | Meaning |
|---|---|
| `--folder <path>` | uSync folder. Default: discovered from `appsettings.json` (`uSync:Settings:RootFolder`), else the highest `uSync/v{n}` under the current directory. |
| `--content` | Also check `Content`, `Media` and `Blueprints`. Off by default. |
| `--format text\|github\|sarif\|junit` | Output format. Default `github` when `GITHUB_ACTIONS=true`, else `text`. |
| `--output <file>` | Write `sarif`/`junit` to a file instead of stdout. |
| `--warnings-as-errors` | Warnings fail the run. |
| `--changed-since <git-ref>` | Only report problems in files changed since that ref (all files are still loaded, so clashes with unchanged files are found). |
| `--summary` | Write a markdown table of the items changed since `--changed-since` (type, alias, added/changed/deleted) to `$GITHUB_STEP_SUMMARY` when set, else stdout. |
| `--publish-folder <path>` | Check the publish output contains the uSync folder with the same files. |

Exit codes: `0` clean, `1` errors (or warnings with `--warnings-as-errors`), `2` the tool itself failed (folder not found, bad arguments).

### Connected commands

- Server and credentials can come from environment variables `USYNC_SERVER`, `USYNC_CLIENT_ID`, `USYNC_CLIENT_SECRET`, as well as `-s`/`-i`/`-k` and appsettings. Command line wins, then env vars, then appsettings.
- `usync-ping --timeout <seconds>` (default 300). Exit `1` if the site never answers.
- `healthcheck-group-check` exits `1` when any result is an error.
- `usync-report [--set <name>]`: dry run of an import, prints what would change. Exit `0` even with changes; `1` if the report itself fails.
- `usync-import` and `usync-report` append a markdown table to `$GITHUB_STEP_SUMMARY` when it's set.
