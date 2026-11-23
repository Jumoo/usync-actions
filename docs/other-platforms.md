# uSync checks and commands on other platforms

All the work happens in the `uSync.Cli` dotnet tool, so any pipeline that can run `dotnet` can run it. The GitHub actions in this repo are thin wrappers; so are these.

Two rules on every platform:

- **Secrets go in environment variables.** The tool reads `USYNC_SERVER`, `USYNC_CLIENT_ID` and `USYNC_CLIENT_SECRET`. Don't pass `-i`/`-k` on the command line, where they can end up in build logs.
- **Exit codes.** `files-verify`: `0` clean, `1` problems found, `2` the tool couldn't run. Connected commands exit non-zero on failure (`usync-ping` after `--timeout` seconds without an answer, `healthcheck-group-check` when a check reports an error).

The tool needs the .NET 10 runtime. The `mcr.microsoft.com/dotnet/sdk:10.0` image has it.

## Azure DevOps

Step templates in [`azure-devops/templates`](../azure-devops/templates): `verify.yml`, `run.yml`, and `setup.yml` (used by both). Reference this repo as a resource:

```yaml
resources:
  repositories:
    - repository: usync
      type: github
      name: Jumoo/usync-actions
      ref: refs/tags/v1
      endpoint: github          # a GitHub service connection

stages:
  - stage: build
    jobs:
      - job: build
        pool: { vmImage: ubuntu-latest }
        steps:
          - checkout: self
          - template: azure-devops/templates/verify.yml@usync
            parameters:
              workingDirectory: src/MySite

  - stage: deploy
    jobs:
      - deployment: site
        environment: production
        pool: { vmImage: windows-latest }
        strategy:
          runOnce:
            deploy:
              steps:
                # ... your deploy steps ...
                - template: azure-devops/templates/run.yml@usync
                  parameters:
                    command: usync-ping
                    args: --timeout 300
                    server: $(SiteUrl)
                    clientId: $(UsyncClientId)
                    clientSecret: $(UsyncClientSecret)   # a secret variable
                - template: azure-devops/templates/run.yml@usync
                  parameters:
                    command: usync-import
                    server: $(SiteUrl)
                    clientId: $(UsyncClientId)
                    clientSecret: $(UsyncClientSecret)
```

`verify.yml` publishes JUnit results, so problems show on the run's Tests tab. Set `publishResults: false` to turn that off.

## GitLab

CI/CD components in [`gitlab/templates`](../gitlab/templates): `verify` and `run`. A CI/CD catalog project needs the `templates/` folder at its root, so these get mirrored to a GitLab project (`jumoo/usync`) on release. Until then, copy the files into your own project and `include: local:`.

```yaml
include:
  - component: $CI_SERVER_FQDN/jumoo/usync/verify@1
    inputs:
      working-directory: src/MySite
      changed-since: origin/$CI_MERGE_REQUEST_TARGET_BRANCH_NAME

  - component: $CI_SERVER_FQDN/jumoo/usync/run@1
    inputs:
      job-name: usync-import
      command: usync-import
      server: https://my-site.example.com

usync-import:
  needs: [deploy-site]
```

Set `USYNC_CLIENT_ID` and `USYNC_CLIENT_SECRET` as masked CI/CD variables.

## Bitbucket Pipelines

```yaml
image: mcr.microsoft.com/dotnet/sdk:10.0

pipelines:
  pull-requests:
    '**':
      - step:
          name: uSync checks
          script:
            - dotnet tool install uSync.Cli --tool-path ./.usync-cli
            - cd src/MySite
            - ../../.usync-cli/uSyncCli files-verify --format junit --output ../../test-results/usync.xml || true
            - ../../.usync-cli/uSyncCli files-verify --format text   # this one fails the step
          # Bitbucket picks up JUnit files under test-results/ by itself.

  branches:
    main:
      - step:
          name: Deploy
          deployment: production
          script:
            - echo "your deploy here"
            - dotnet tool install uSync.Cli --tool-path ./.usync-cli
            # USYNC_SERVER, USYNC_CLIENT_ID, USYNC_CLIENT_SECRET are secured deployment variables
            - ./.usync-cli/uSyncCli usync-ping --timeout 300
            - ./.usync-cli/uSyncCli usync-import
```

## TeamCity

Add a **Command Line** build step (or a Kotlin DSL `script` step). Store the client id and secret as password parameters named `env.USYNC_CLIENT_ID` and `env.USYNC_CLIENT_SECRET`, so TeamCity exports them as environment variables and masks them in logs.

```kotlin
steps {
    script {
        name = "uSync checks"
        workingDir = "src/MySite"
        scriptContent = """
            dotnet tool update uSync.Cli --tool-path %system.teamcity.build.tempDir%/usync-cli
            %system.teamcity.build.tempDir%/usync-cli/uSyncCli files-verify --format junit --output usync.xml
        """.trimIndent()
    }
    // after the deploy step
    script {
        name = "uSync import"
        scriptContent = """
            dotnet tool update uSync.Cli --tool-path %system.teamcity.build.tempDir%/usync-cli
            %system.teamcity.build.tempDir%/usync-cli/uSyncCli usync-ping --timeout 300
            %system.teamcity.build.tempDir%/usync-cli/uSyncCli usync-import
        """.trimIndent()
    }
}
features {
    xmlReport {
        reportType = XmlReport.XmlReportType.JUNIT
        rules = "src/MySite/usync.xml"
    }
}
```

Set `env.USYNC_SERVER` as a parameter too, or pass `-s https://my-site` (the URL isn't secret).

## Octopus Deploy

Most IIS deploys run through Octopus, so the post-deploy import fits as a **Run a Script** step after the IIS deploy step, running on the worker or the web server.

Project variables: `uSync.Server` (text), `uSync.ClientId` (text), `uSync.ClientSecret` (**sensitive**).

```powershell
$ErrorActionPreference = 'Stop'
$toolPath = Join-Path $env:TEMP 'usync-cli'
dotnet tool update uSync.Cli --tool-path $toolPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$env:USYNC_SERVER        = $OctopusParameters['uSync.Server']
$env:USYNC_CLIENT_ID     = $OctopusParameters['uSync.ClientId']
$env:USYNC_CLIENT_SECRET = $OctopusParameters['uSync.ClientSecret']

& "$toolPath\uSync.exe" usync-ping --timeout 300
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& "$toolPath\uSync.exe" usync-import
exit $LASTEXITCODE
```

Run the file checks in your build server before packaging, not in Octopus: by the time Octopus has the package, the files are already merged.

## Your own machine

```powershell
dotnet tool install --global uSync.Cli
uSyncCli files-verify
```

Or as a git pre-commit hook (`.git/hooks/pre-commit`):

```sh
#!/bin/sh
cd src/MySite && uSyncCli files-verify --format text
```
