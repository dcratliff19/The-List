# Standalone PowerShell regression checks; no GitHub/network access is used.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$prepare = Join-Path $PSScriptRoot '../prepare-sqlite-windows.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('the-list-sqlite-' + [Guid]::NewGuid().ToString('N'))
$native = Join-Path $fixture 'native'
$package = Join-Path $native 'package'
New-Item -ItemType Directory -Path (Join-Path $native '.dart_tool'), (Join-Path $package 'lib/src/hook') -Force | Out-Null
$bytes = [Text.Encoding]::UTF8.GetBytes('verified SQLite fixture')
$sample = Join-Path $fixture 'sample.dll'
[IO.File]::WriteAllBytes($sample, $bytes)
$hash = (Get-FileHash -LiteralPath $sample -Algorithm SHA256).Hash.ToLowerInvariant()
$cache = Join-Path $native ('.dart_tool/hooks_runner/shared/sqlite3/build/download-' + $hash.Substring(0, 8))
$dll = Join-Path $cache 'sqlite3.dll'
$metadata = Join-Path $package 'lib/src/hook/asset_hashes.dart'
@"
packages:
  sqlite3:
    description:
      url: "https://pub.dev"
    source: hosted
    version: "3.5.2"
"@ | Set-Content -LiteralPath (Join-Path $native 'pubspec.lock')
@{ packages = @(@{ name = 'sqlite3'; rootUri = '../package/' }) } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $native '.dart_tool/package_config.json')
"const String? releaseTag = 'sqlite3-3.5.2';`nconst hashes = {'sqlite3.x64.windows.dll': '$hash'};" |
    Set-Content -LiteralPath $metadata

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Expect-Rejection([scriptblock]$Action, [string]$Message) {
    try { & $Action } catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw }
        return
    }
    throw "Expected rejection: $Message"
}
function Invoke-WebRequest {
    param([string]$Uri, [string]$OutFile, [int]$TimeoutSec)
    Assert ($Uri -eq 'https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.5.2/sqlite3.x64.windows.dll') 'Download must use the locked upstream release.'
    Assert ($TimeoutSec -eq 60) 'HTTP calls must have a timeout.'
    $global:sqlitePreparationTestCalls++
    switch ($global:sqlitePreparationTestDownloads.Dequeue()) {
        'http-error' { throw 'HTTP 503' }
        'bad' { [IO.File]::WriteAllBytes($OutFile, [Text.Encoding]::UTF8.GetBytes('error page')) }
        'good' { [IO.File]::WriteAllBytes($OutFile, $bytes) }
    }
}
function Start-Sleep { param([int]$Seconds) Assert ($Seconds -eq 2) 'Retries must back off.' }
function Reset-Downloads([string[]]$Responses) {
    $global:sqlitePreparationTestCalls = 0
    $global:sqlitePreparationTestDownloads = [Collections.Generic.Queue[string]]::new()
    foreach ($response in $Responses) { $global:sqlitePreparationTestDownloads.Enqueue($response) }
}
function Prepare { & $prepare -NativeDirectory $native -MaximumAttempts 2 | Out-Null }

try {
    Reset-Downloads @('good')
    Prepare
    Assert ($global:sqlitePreparationTestCalls -eq 1 -and (Get-FileHash -LiteralPath $dll).Hash -ieq $hash) 'Cold cache must contain verified bytes.'

    Reset-Downloads @()
    Prepare
    Assert ($global:sqlitePreparationTestCalls -eq 0) 'Verified cache must avoid a download.'

    Set-Content -LiteralPath $dll -Value 'corrupt cache'
    Reset-Downloads @('http-error', 'good')
    Prepare
    Assert ($global:sqlitePreparationTestCalls -eq 2 -and (Get-FileHash -LiteralPath $dll).Hash -ieq $hash) 'HTTP failure must retry and replace a corrupt cache with verified bytes.'

    Remove-Item -LiteralPath $dll
    Reset-Downloads @('bad', 'good')
    Prepare
    Assert ($global:sqlitePreparationTestCalls -eq 2 -and (Get-FileHash -LiteralPath $dll).Hash -ieq $hash) 'Checksum failure must retry before accepting the file.'

    Remove-Item -LiteralPath $dll
    Reset-Downloads @('bad', 'bad')
    Expect-Rejection { Prepare } 'checksum mismatch'
    Assert (-not (Test-Path -LiteralPath $dll)) 'Invalid bytes must never become the cached DLL.'
    Assert (@(Get-ChildItem -LiteralPath $cache -Filter '*.tmp').Count -eq 0) 'Failed downloads must not leave temporary files.'

    Reset-Downloads @('http-error', 'http-error')
    Expect-Rejection { Prepare } 'HTTP 503'
    Assert ($global:sqlitePreparationTestCalls -eq 2) 'HTTP failures must stop after the retry limit.'

    Set-Content -LiteralPath $metadata -Value "const String? releaseTag = 'sqlite3-9.9.9';"
    Reset-Downloads @()
    Expect-Rejection { Prepare } 'does not match pubspec.lock'
    Assert ($global:sqlitePreparationTestCalls -eq 0) 'Mismatched package metadata must fail before downloading.'
    Write-Output 'Passed 7 SQLite preparation cases; all downloads mocked.'
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolvedFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolvedFixture -Leaf) -notmatch '^the-list-sqlite-[0-9a-f]{32}$') {
        throw 'Refusing to clean an unexpected fixture path.'
    }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
