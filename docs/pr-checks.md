# Check uSync files on pull requests

The `verify` action checks the uSync files in a pull request before anyone imports them. It finds what breaks an import or quietly loses changes: merge conflict markers, broken XML, two items with the same key or alias, and delete markers that clash with live items.

It only reads the files in the repo. It doesn't need a site, a database or any secrets, so it's safe to run on every pull request, including ones from forks.

## Quick start

Add `.github/workflows/usync-checks.yml` to your site's repo:

```yaml
name: uSync checks

on:
  pull_request:
    paths:
      - '**/uSync/**'
      - '**/appsettings*.json'

permissions:
  contents: read

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - uses: Jumoo/usync-actions/verify@v1
        with:
          working-directory: src/MySite   # the folder with appsettings.json
```

Set `working-directory` to your site's folder, the one with `appsettings.json`. The action finds the uSync folder from `uSync:Settings:RootFolder` there, or uses the highest `uSync/v{n}` folder. If your repo has the site at the root, leave it out.

The `paths` filter means the check only runs when uSync files or settings change. Drop it if you want it on every pull request.

## What you see

Problems show as annotations on the pull request's **Files changed** tab, on the file, and on the line where there is one, such as a conflict marker. The check fails if it finds errors.

| Errors (fail the check) | Warnings (reported only) |
|---|---|
| Merge conflict markers, including inside CDATA values | References to keys no file defines (compositions, data types, templates) |
| `.config` files that aren't valid XML | Files exported by an older uSync than the site uses |
| Two files of the same type with the same `Key` | Unknown folders, or files that aren't `.config` |
| Two items of the same type with the same `Alias` and different keys | Content with no matching content type file |
| A delete marker and a live item with the same `Key` | |

Content, Media and Blueprints aren't checked unless you set `content: true`.

## Only report what the pull request changed

On a site with years of uSync history, the first run may turn up old warnings nobody is going to fix in this pull request. `changed-since` limits the report to files the pull request changed:

```yaml
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0   # changed-since needs the base branch's history

      - uses: Jumoo/usync-actions/verify@v1
        with:
          working-directory: src/MySite
          changed-since: origin/${{ github.base_ref }}
          summary: true
```

Every file is still loaded, so a new file that clashes with an old one is still caught. Only the report is filtered.

`summary: true` adds a table to the run's summary page, listing the document types, data types and content the branch changes. Reviewers can see what the pull request will do to the site without reading the XML.

## Make it required

To stop a pull request merging until its uSync files pass:

1. Merge the workflow to your default branch, and let it run once on a pull request so GitHub knows the check's name.
2. In the repo, go to **Settings > Branches** (or **Rules > Rulesets**) and add a rule for your default branch.
3. Turn on **Require status checks to pass**, and add **verify**, the job name from the workflow.

## Stricter or looser

| You want to | Set |
|---|---|
| Fail on warnings too | `warnings-as-errors: true` |
| Check Content, Media and Blueprints as well | `content: true` |
| Use a uSync folder the action can't find on its own | `folder: uSync/v17` (relative to `working-directory`) |
| Report problems without failing the check | `continue-on-error: true` on the step, then read `steps.<id>.outputs.exit-code` |
| Pin the tool version | `version: 17.2.1` |

## Keep results in the Security tab

With `sarif: true`, the action also writes a SARIF report and uploads it to code scanning. The results then show in the repo's **Security** tab and stay there between runs. The job needs one more permission:

```yaml
permissions:
  contents: read
  security-events: write
```

Code scanning is free on public repos. A private repo needs GitHub Code Security (part of GitHub Advanced Security), or the upload step fails. Without it, leave `sarif` off, or set `upload-sarif: false` to write the file without uploading it.

## Check it on your machine first

The action wraps the [uSync.Cli](https://github.com/Jumoo/uSync.CommandLine) tool, so you can run the same check before you push:

```
dotnet tool install --global uSync.Cli
uSyncCli files-verify
```

Run it from the site folder. `uSyncCli files-verify --changed-since origin/main` matches the pull request check.

## Also check the deploy

The same action can check that a publish output still contains the uSync folder. Add `publish-folder` in your deploy workflow, after `dotnet publish`:

```yaml
      - uses: Jumoo/usync-actions/verify@v1
        with:
          working-directory: src/MySite
          publish-folder: ${{ github.workspace }}/publish
```

This catches a `.csproj` change that stops the uSync files being copied, before the deploy goes out with nothing to import.

## More

- [examples/pr-checks.yml](../examples/pr-checks.yml): the full pull request workflow, with every option above.
- [The verify inputs and outputs](../README.md#verify), in the README.
- [Other platforms](other-platforms.md): the same check on Azure DevOps, GitLab, Bitbucket and TeamCity.
