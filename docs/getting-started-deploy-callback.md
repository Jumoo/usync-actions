# Getting started: import after deploy without waiting

This guide sets up a deploy where GitHub Actions stops as soon as the files are on the server. When the site starts the new build, it tells GitHub, and a second workflow runs the uSync import.

It takes about 15 minutes. You'll need:

- An Umbraco 17 site using uSync, deployed from GitHub Actions. The examples deploy to an Azure Web App, and any host works.
- Admin rights on the GitHub repo.
- An Umbraco API user for uSync.Cli. If you don't have one yet, see [Create an API user](https://github.com/Jumoo/uSync.CommandLine#create-an-api-user).

For how it works and every setting, see [deploy-callback.md](deploy-callback.md).

---

## Step 1: Add the package to the site

```
dotnet add package uSync.Command.Notify
```

This adds a **uSync Site Started** webhook event. It fires once each time the site starts a build it hasn't announced before.

## Step 2: Create the webhook file

Install the uSync command line tool if you don't have it:

```
dotnet tool install --global uSync.Cli
```

From the site folder (where `appsettings.json` is), run:

```
uSyncCli files-webhook --repo my-org/my-site
```

Use your own repo instead of `my-org/my-site`. This writes a file like `uSync/v17/Webhooks/7d0a8be7-....config`.

Commit the file. uSync imports it with your other settings, so every environment gets the webhook. The file doesn't contain the token, only its name, so it's safe in source control.

> **Prefer the backoffice?** In **Settings > Webhooks**, create a webhook with:
>
> - **URL:** `https://api.github.com/repos/my-org/my-site/dispatches`
> - **Events:** uSync Site Started
> - **Headers:** `Accept` = `application/vnd.github+json`, and `uSync-Notify-Token` = `GitHubToken`
>
> Save it, and commit the file uSync exports to `uSync/v17/Webhooks`.

## Step 3: Create a GitHub token for the site

The site needs a token to start a workflow in your repo.

1. In GitHub, go to **Settings > Developer settings > Fine-grained tokens > [Generate new token](https://github.com/settings/personal-access-tokens/new)**.
2. **Repository access:** only select your site's repo.
3. **Permissions:** set **Contents** to **Read and write**. That's all it needs.
4. Choose an expiry and copy the token.

> The token belongs to whoever creates it. For a team, a GitHub App or a token from a shared bot account is better.

## Step 4: Give the site the token

Add an app setting or environment variable on the site. For an Azure Web App, that's **Settings > Environment variables**:

| Name | Value |
|---|---|
| `uSync__Notify__Secrets__GitHubToken` | the token from step 3 |

Don't put the token in `appsettings.json` or the webhook. The package adds it to the request when the webhook sends, and only to `api.github.com`.

## Step 5: Add the workflows

Copy these two files into `.github/workflows/` in your repo:

- [deploy-callback.yml](../examples/deploy-callback.yml) builds, checks and deploys, then stops.
- [deploy-result.yml](../examples/deploy-result.yml) runs when the site calls back, and imports.

Change the publish path (`src/MySite`) and the deploy step to match your site.

Then set these under the repo's **Settings > Secrets and variables > Actions**:

| Type | Name | Value |
|---|---|---|
| Variable | `SITE_URL` | `https://my-site.azurewebsites.net` |
| Variable | `AZURE_WEBAPP_NAME` | your web app's name |
| Secret | `AZURE_PUBLISH_PROFILE` | the web app's publish profile |
| Secret | `USYNC_CLIENT_ID` | the API user's client id |
| Secret | `USYNC_CLIENT_SECRET` | the API user's client secret |

`deploy-result.yml` must be on your **default branch**. GitHub only runs `repository_dispatch` and scheduled workflows from there.

## Step 6: Deploy and check it worked

Push to `main`. You should see:

1. **The Deploy workflow** finishes straight after the deploy step. Its summary says "Deployment … is waiting for the site to call back".
2. **About a minute after the site starts**, the **Deploy result** workflow starts on its own, triggered by `repository_dispatch`.
3. **It imports uSync**, the job summary lists the changes, and the deployment on the repo's front page (**Deployments**) turns green.

On the site, in **Settings > Webhooks**, open the webhook's log. You should see a request with status **204 No Content**.

---

## If it doesn't work

| What you see | Likely cause |
|---|---|
| No entry in the webhook log | The package isn't on the site, or the webhook didn't import. Check uSync imported the Webhooks folder. If the site already announced this build, it won't send again; deploy a new commit. |
| Webhook log: **403 Forbidden** | The package refused to send the token. The Umbraco log has a warning saying why: either `uSync__Notify__Secrets__GitHubToken` isn't set (or the site hasn't restarted since you set it), or the webhook URL isn't `https://api.github.com/...`. |
| Webhook log: **401** from GitHub | The token is wrong or has expired. |
| Webhook log: **404** from GitHub | Wrong repo name, or the token can't see that repo. |
| Webhook log: **204**, but no workflow runs | `deploy-result.yml` isn't on the default branch, or its `types:` doesn't match `usync-site-started`. |
| Deploy result says "Nothing waiting" | The site's revision didn't match the deployed commit. Check the payload's `revision` in the webhook log. If it's empty or different, set `uSync__Notify__Revision` to the commit SHA in your deploy step. |
| The deployment fails hours later with "No callback from the site" | The six-hourly backstop found it still waiting and the site didn't answer. Look at the webhook log and the site's startup. |

## Optional settings

All are set on the site, as `uSync__Notify__...` environment variables or `uSync:Notify` in appsettings.

- **`Environment`** names the environment in the payload, useful when one repo deploys to several sites.
- **`Revision`** sets the build ID yourself instead of reading it from the assembly.
- **`AllowedHosts`** adds hosts the token may be sent to, if you send the webhook somewhere other than GitHub.
- **`EventType`** changes the dispatch `event_type`. If you change it, change `types:` in `deploy-result.yml` to match.

To change how often the backstop runs, edit the `cron` in `deploy-result.yml`. Each run bills at least a minute, so every six hours is about 120 minutes a month.
