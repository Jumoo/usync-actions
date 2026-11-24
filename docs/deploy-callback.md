# Import after deploy without waiting for the site

New to this? Start with the step-by-step [getting started guide](getting-started-deploy-callback.md).

After a deploy, the usual pipeline runs `usync-ping` and waits for the site to restart before it imports. That wait is runner time you pay for. On a slow-starting site it's several minutes per deploy.

With the callback, the deploy workflow finishes as soon as the files are on the server. When the site starts the new build, it tells GitHub, and a second workflow runs the import.

```
deploy-callback.yml                site                          deploy-result.yml
-------------------                ----                          -----------------
publish, verify, deploy
record a GitHub deployment  ──>    restarts, starts new build
(waiting, for this commit)         "uSync Site Started" webhook ──> find the deployment by commit
done                                                               usync-report, usync-import
                                                                   mark it success / failure
```

A scheduled run of `deploy-result.yml` catches callbacks that never come: a site that didn't start, a webhook that failed. Deployments still waiting after 30 minutes get one check, and a site that doesn't answer fails its deployment.

## What you need

- **[uSync.Command.Notify](https://www.nuget.org/packages/uSync.Command.Notify)** on the site. It adds the "uSync Site Started" webhook event.
- **A webhook** for that event, pointing at your repo's `repository_dispatch` API. The `files-webhook` command writes it into your uSync folder (below).
- **A GitHub token** on the site that can send the dispatch.
- **The two workflows**, [deploy-callback.yml](../examples/deploy-callback.yml) and [deploy-result.yml](../examples/deploy-result.yml), with the API user secrets the [run action](../README.md#api-user) uses. `deploy-result.yml` must be on the default branch.

## 1. Add the package

```
dotnet add package uSync.Command.Notify
```

## 2. Add the webhook

From your site folder:

```
uSyncCli files-webhook --repo my-org/my-site
```

That writes `uSync/v17/Webhooks/{key}.config`. Commit it. uSync imports it like any other setting, so every environment gets the webhook. Running it again rewrites the same file.

The file names the token but doesn't hold it, so it's safe to commit:

```xml
<Webhook Key="..." Alias="https://api.github.com/repos/my-org/my-site/dispatches" Level="0">
  <Url>https://api.github.com/repos/my-org/my-site/dispatches</Url>
  <Enabled>true</Enabled>
  <Name>uSync site started (my-org/my-site)</Name>
  <Description>Tells the deploy pipeline the site is running a new build. Token comes from uSync:Notify:Secrets on the site.</Description>
  <ContentTypeKeys />
  <Events>
    <Event>uSyncSiteStarted</Event>
  </Events>
  <Headers>
    <Header Key="Accept"><![CDATA[application/vnd.github+json]]></Header>
    <Header Key="uSync-Notify-Token"><![CDATA[GitHubToken]]></Header>
  </Headers>
</Webhook>
```

**Without the command:** in the backoffice, go to Settings > Webhooks and create one:

| Field | Value |
|---|---|
| URL | `https://api.github.com/repos/{owner}/{repo}/dispatches` |
| Events | uSync Site Started |
| Headers | `Accept: application/vnd.github+json` and `uSync-Notify-Token: GitHubToken` |

uSync exports it to the Webhooks folder when you save, so commit that file.

## 3. Give the site a token

Create a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new) for the one repo, with **Contents: Read and write**, the permission `repository_dispatch` needs. A GitHub App installation token works too, and doesn't belong to a person.

Set it on the site as an app setting or environment variable:

```
uSync__Notify__Secrets__GitHubToken = github_pat_...
```

When the webhook sends, the package swaps the `uSync-Notify-Token: GitHubToken` header for `Authorization: Bearer <token>`. The token is never stored in the database, and Umbraco's webhook log shows only the name.

The token is only sent to hosts in `uSync:Notify:AllowedHosts`, over https. The default is `api.github.com`. This stops someone with webhook access in the backoffice pointing a webhook at their own server to collect the token.

Fine-grained tokens expire. When the token expires the webhook gets a 401 from GitHub (it shows in the webhook log), and the scheduled run picks up the deployment instead.

## 4. Add the workflows

Copy [deploy-callback.yml](../examples/deploy-callback.yml) and [deploy-result.yml](../examples/deploy-result.yml) to `.github/workflows/`, and set the variables and secrets listed at the top of each.

## How the deployment is matched

The site sends the commit it's running as `client_payload.revision`. It reads it from the site assembly's informational version (`1.0.0+<commit sha>`). The .NET SDK sets that when it builds in a git checkout, so a `dotnet publish` after `actions/checkout` has it.

`deploy-callback.yml` records a GitHub deployment for `github.sha` with the task `usync`, and `deploy-result.yml` looks for one with that commit that's still waiting.

If your build doesn't set the version that way, set the revision on the site in the deploy step instead:

```
uSync__Notify__Revision = <the commit sha>
```

The site sends one callback per new revision. An app pool recycle, a scale out or a restart of the same build sends nothing. If the revision can't be found, it sends on every start, and `deploy-result.yml` takes the newest waiting deployment.

## Settings

All under `uSync:Notify` in appsettings, or `uSync__Notify__...` as environment variables.

| Setting | Default | |
|---|---|---|
| `Secrets:{name}` | | Tokens a webhook can name with the `uSync-Notify-Token` header. |
| `AllowedHosts` | `["api.github.com"]` | Hosts a token may be sent to. |
| `Revision` | from the site assembly | The build the site is running. |
| `Environment` | the ASP.NET Core environment | Sent as `client_payload.environment`, for telling sites apart when one repo deploys to several. |
| `EventType` | `usync-site-started` | The `event_type` sent, which is what the workflow's `repository_dispatch: types:` listens for. |

## Payload

```json
{
  "event_type": "usync-site-started",
  "client_payload": {
    "revision": "4f1c2e9...",
    "environment": "Production",
    "machine": "web-1",
    "startedUtc": "2026-11-24T13:14:15.66Z"
  }
}
```

It's plain JSON, so the same event can go to Azure DevOps, GitLab or any other receiver. Point the webhook's URL there and leave out the token header, or add the host to `AllowedHosts`.

## Things to know

- **Timing.** Umbraco sends webhooks from a background job, so the callback arrives about a minute after the site starts.
- **Load balancing.** Only the scheduling publisher server sends webhooks, so one start sends one callback.
- **What it saves.** It saves the time `usync-ping` would spend waiting, plus a minute for rounding, since the result workflow is a separate job. An Azure Web App that restarts in under a minute saves little. A site that takes several minutes to start saves several minutes per deploy. Deploys from self-hosted runners don't use paid minutes anyway.
- **The backstop costs minutes too.** At every six hours, that's about 120 billed minutes a month, whether or not anything was waiting. Set the cron to suit how often you deploy.
- **Two deployments show.** Jobs with an `environment:` create their own GitHub deployment. The example deploy job doesn't set one, so only the `usync` deployment appears. If you add an environment for its secrets, you'll see both.
