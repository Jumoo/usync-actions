# uSync actions

Build and deploy pipeline steps for Umbraco sites that use [uSync](https://jumoo.co.uk/usync).

- **verify** checks the uSync files in your repo on every pull request: merge conflict markers, invalid XML, two files with the same key, two items with the same alias, delete markers that clash with live items. No site, database or secrets needed.
- **run** talks to a running site after a deploy: wait for it to come up, run an import, rebuild caches, run health checks.
- **setup** installs the tool, if you want to call it yourself.

All three are thin wrappers around the [`uSync.Cli`](https://github.com/Jumoo/uSync.CommandLine) dotnet tool, so the same checks run on your own machine and on other CI platforms (Azure DevOps, GitLab, Bitbucket, TeamCity, Octopus).

## Status

Work in progress. The first release (`v1`) is on its way; until it's tagged, the `@v1` references you may see won't resolve.

## License

MPL-2.0, the same as uSync.
