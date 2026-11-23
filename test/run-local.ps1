<#
.SYNOPSIS
    Runs the same uSync.Cli checks as .github/workflows/test.yml against test/fixtures, locally.

.DESCRIPTION
    Installs uSync.Cli into a temporary tool folder (from .local-feed by default, so you can
    test a build before it is on nuget.org), runs `files-verify` in each fixture and checks
    the exit code against the fixture's expected.json.

.PARAMETER Feed
    Folder (or URL) to install uSync.Cli from. Default: .local-feed in the repo root.
    Pass '' to install from nuget.org.

.PARAMETER Version
    uSync.Cli version. Default: the newest uSync.Cli.*.nupkg in -Feed.

.EXAMPLE
    ./test/run-local.ps1
#>
[CmdletBinding()]
param(
    [string] $Feed = (Join-Path $PSScriptRoot '..' '.local-feed'),
    [string] $Version
)

$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
$fixtures = Join-Path $PSScriptRoot 'fixtures'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) {
        Write-Host "  PASS  $name (exit $actual)" -ForegroundColor Green
    } else {
        Write-Host "  FAIL  $name (expected $expected, got $actual)" -ForegroundColor Red
        $failures.Add($name)
    }
}

# --- install -------------------------------------------------------------------------
$installArgs = @('tool', 'install', 'uSync.Cli')
if ($Feed) {
    if (-not (Test-Path $Feed)) {
        throw "Feed folder '$Feed' not found. Build uSync.Cli into it, or pass -Feed '' to use nuget.org."
    }
    $Feed = (Resolve-Path $Feed).Path
    if (-not $Version) {
        $pkg = Get-ChildItem $Feed -Filter 'uSync.Cli.*.nupkg' |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $pkg) { throw "No uSync.Cli.*.nupkg in '$Feed'." }
        $Version = $pkg.Name -replace '^uSync\.Cli\.', '' -replace '\.nupkg$', ''
    }
    # --add-source fails under package source mapping, so use a config of our own.
    $nugetConfig = Join-Path ([System.IO.Path]::GetTempPath()) "usync-actions-nuget-$PID.config"
    $feedXml = [System.Security.SecurityElement]::Escape($Feed)
    @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="usync-extra" value="$feedXml" />
  </packageSources>
  <packageSourceMapping><clear /></packageSourceMapping>
</configuration>
"@ | Set-Content -Path $nugetConfig -Encoding utf8
    $installArgs += @('--configfile', $nugetConfig)
}
if ($Version) { $installArgs += @('--version', $Version) }

$toolPath = Join-Path ([System.IO.Path]::GetTempPath()) "usync-actions-test-$PID"
$installArgs += @('--tool-path', $toolPath)

Write-Host "Installing uSync.Cli $Version into $toolPath"
& dotnet @installArgs
if ($LASTEXITCODE -ne 0) { throw "dotnet tool install failed ($LASTEXITCODE)" }

# uSyncCli is the tool command; uSync is kept as a fallback.
$cli = @('uSyncCli.exe', 'uSyncCli', 'uSync.exe', 'uSync') |
    ForEach-Object { Join-Path $toolPath $_ } |
    Where-Object { Test-Path $_ -PathType Leaf } |
    Select-Object -First 1
if (-not $cli) { throw "Neither uSync nor uSyncCli found in $toolPath" }
Write-Host "Using $cli"

try {
    # An older uSync.Cli exits 1 for an unknown command, which would make every
    # "must fail" fixture pass by accident. Stop early instead.
    $help = & $cli --help 2>&1 | Out-String
    if ($help -notmatch '\bfiles-verify\b') {
        throw "This uSync.Cli ($Version) has no files-verify command. Build one with it into the feed."
    }

    # --- fixtures --------------------------------------------------------------------
    foreach ($dir in Get-ChildItem $fixtures -Directory | Sort-Object Name) {
        $expected = Get-Content (Join-Path $dir.FullName 'expected.json') -Raw | ConvertFrom-Json -AsHashtable
        Write-Host "`n$($dir.Name)"
        foreach ($case in $expected.GetEnumerator() | Sort-Object Key) {
            $extra = @($case.Key -split ' ' | Where-Object { $_ })
            Push-Location $dir.FullName
            try {
                & $cli files-verify --format text @extra | Out-Host
                $code = $LASTEXITCODE
            } finally { Pop-Location }
            Assert-Equal "$($dir.Name) files-verify $($case.Key)".TrimEnd() $case.Value $code
        }
    }

    # --- tool failure is exit 2, not 1 -----------------------------------------------
    Write-Host "`nmissing folder"
    Push-Location $fixtures
    try {
        & $cli files-verify --format text --folder does-not-exist | Out-Host
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    Assert-Equal 'files-verify --folder does-not-exist' 2 $code

    # --- formats the actions rely on -------------------------------------------------
    Write-Host "`nformats"
    $out = Join-Path $toolPath 'out'
    New-Item -ItemType Directory $out -Force | Out-Null
    Push-Location (Join-Path $fixtures 'alias-clash')
    try {
        $github = & $cli files-verify --format github 2>&1 | Out-String
        Assert-Equal 'github format writes ::error' $true ($github -match '::error')

        & $cli files-verify --format sarif --output (Join-Path $out 'usync.sarif') | Out-Null
        $sarif = Get-Content (Join-Path $out 'usync.sarif') -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
        Assert-Equal 'sarif output has results' $true ([bool]($sarif -and $sarif.runs -and $sarif.runs[0].results))

        & $cli files-verify --format junit --output (Join-Path $out 'usync.xml') | Out-Null
        $junit = Test-Path (Join-Path $out 'usync.xml')
        Assert-Equal 'junit output written' $true $junit
    } finally { Pop-Location }

    # --- the two verify action files must match --------------------------------------
    Write-Host "`nactions"
    $same = (Get-FileHash (Join-Path $repo 'action.yml')).Hash -eq (Get-FileHash (Join-Path $repo 'verify/action.yml')).Hash
    Assert-Equal 'action.yml matches verify/action.yml' $true $same
}
finally {
    Remove-Item $toolPath -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($failures.Count) {
    Write-Host "$($failures.Count) failed: $($failures -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host 'All passed' -ForegroundColor Green
