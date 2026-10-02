<#
.SYNOPSIS
Downloads and verifies the locked SQLite Windows runtime before Flutter hooks run.
.DESCRIPTION
Run after flutter pub get. A failed HTTP response or corrupt download is retried,
never accepted as a DLL. SQLite's build hook also verifies the populated cache.
#>
[CmdletBinding()]
param(
    [string]$NativeDirectory = (Join-Path $PSScriptRoot '../native'),
    [ValidateRange(1, 5)][int]$MaximumAttempts = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$native = [IO.Path]::GetFullPath($NativeDirectory)
$lock = Get-Content -LiteralPath (Join-Path $native 'pubspec.lock') -Raw
$entry = [regex]::Match($lock, '(?ms)^  sqlite3:\r?\n(?<entry>.*?)(?=^  \S|\z)').Groups['entry'].Value
$version = [regex]::Match($entry, '(?m)^    version: "(?<version>\d+\.\d+\.\d+)"').Groups['version'].Value
if (-not $version -or $entry -notmatch '(?m)^    source: hosted\r?$' -or
    $entry -notmatch 'url: "https://pub.dev"') {
    throw 'Expected a locked, pub.dev-hosted sqlite3 dependency.'
}

$configPath = Join-Path $native '.dart_tool/package_config.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$packages = @($config.packages | Where-Object name -eq 'sqlite3')
if ($packages.Count -ne 1) { throw 'Run flutter pub get before preparing SQLite.' }
$packageRoot = [Uri]::new([Uri]::new($configPath), [string]$packages[0].rootUri).LocalPath
$metadata = Get-Content -LiteralPath (Join-Path $packageRoot 'lib/src/hook/asset_hashes.dart') -Raw
$releaseTag = "sqlite3-$version"
if (-not $metadata.Contains("releaseTag = '$releaseTag'")) {
    throw 'SQLite package metadata does not match pubspec.lock. Run flutter pub get.'
}
$hash = [regex]::Match($metadata, "'sqlite3\.x64\.windows\.dll':\s*'(?<hash>[a-f0-9]{64})'").Groups['hash'].Value
if (-not $hash) { throw 'The locked SQLite package has no Windows x64 checksum.' }

# Flutter 3.47.5/Dart 3.13 use this shared native hook output directory. The
# package names its cache by checksum and re-verifies its contents before use.
$cache = Join-Path $native ('.dart_tool/hooks_runner/shared/sqlite3/build/download-' + $hash.Substring(0, 8))
$dll = Join-Path $cache 'sqlite3.dll'
if ((Test-Path -LiteralPath $dll -PathType Leaf) -and
    (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash -ieq $hash) {
    Write-Output "Verified cached SQLite $version Windows x64 runtime."
    return
}

New-Item -ItemType Directory -Path $cache -Force | Out-Null
$temporary = Join-Path $cache ('download-' + [Guid]::NewGuid().ToString('N') + '.tmp')
$url = "https://github.com/simolus3/sqlite3.dart/releases/download/$releaseTag/sqlite3.x64.windows.dll"
try {
    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            # Invoke-WebRequest rejects HTTP errors; the dependency's downloader
            # can otherwise report the hash of an error page as a DLL mismatch.
            Invoke-WebRequest -Uri $url -OutFile $temporary -TimeoutSec 60
            $actual = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash
            if ($actual -ine $hash) {
                throw "SQLite checksum mismatch: expected $hash, received $actual."
            }
            Move-Item -LiteralPath $temporary -Destination $dll -Force
            Write-Output "Downloaded and verified SQLite $version Windows x64 runtime."
            return
        } catch {
            if ($attempt -eq $MaximumAttempts) { throw }
            Write-Warning "SQLite download attempt $attempt failed: $($_.Exception.Message) Retrying."
            Start-Sleep -Seconds 2
        }
    }
} finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) {
        Remove-Item -LiteralPath $temporary
    }
}
