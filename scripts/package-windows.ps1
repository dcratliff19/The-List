<#
.SYNOPSIS
Packages the complete Flutter Windows x64 release and its user documentation.
.DESCRIPTION
Run after `flutter build windows --release` from native/. The version comes from
pubspec.yaml. Optional release tags must match the semantic version (without the
Flutter build number). Existing packages are never overwritten.
#>
[CmdletBinding()]
param(
    [string]$BuildDirectory = (Join-Path $PSScriptRoot '../native/build/windows/x64/runner/Release'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../dist'),
    [string]$Tag = '',
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifest = Get-Content -LiteralPath (Join-Path $repositoryRoot 'native/pubspec.yaml') -Raw
$versionMatch = [regex]::Match($manifest, '(?m)^version:\s*(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+\d+)?)\s*$')
if (-not $versionMatch.Success) {
    throw 'Expected a semantic version with an optional numeric build number in native/pubspec.yaml.'
}
$version = $versionMatch.Groups[1].Value
$releaseVersion = $version.Split('+')[0]
if ($Tag -and $Tag -cne "v$releaseVersion") {
    throw "Tag '$Tag' must match pubspec.yaml: v$releaseVersion (app version $version)."
}
if ($ValidateOnly) {
    Write-Output "Validated app version $version; release tag v$releaseVersion."
    return
}

# Restrict staging and output to this checkout. In particular, cleanup must never
# traverse an arbitrary caller-supplied folder outside the repository.
function Get-WorkspacePath([string]$Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    $prefix = $repositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must be inside the repository: $absolute"
    }
    return $absolute
}

$buildPath = Get-WorkspacePath $BuildDirectory
$outputPath = Get-WorkspacePath $OutputDirectory
if ($outputPath.Equals($buildPath, [StringComparison]::OrdinalIgnoreCase) -or
    $outputPath.StartsWith($buildPath.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The output directory must not be inside the runtime being packaged.'
}
foreach ($relative in @('the_list.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets')) {
    if (-not (Test-Path -LiteralPath (Join-Path $buildPath $relative))) {
        throw "Incomplete Windows release: missing $relative. Run flutter build windows --release first."
    }
}

$guidePath = Join-Path $repositoryRoot 'docs/USER_GUIDE.md'
$guide = Get-Content -LiteralPath $guidePath -Raw
# Only distribute the guide's sample images, not unrelated/private screenshots.
$imageMatches = [regex]::Matches($guide, '\.\./screenshots/([A-Za-z0-9_-]+\.(?:png|jpe?g|webp))')
$images = @($imageMatches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
foreach ($name in $images) {
    if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot "screenshots/$name") -PathType Leaf)) {
        throw "Missing guide image: $name"
    }
}

$packageName = "The-List-$version-Windows-x64"
$zipPath = Join-Path $outputPath "$packageName.zip"
$checksumPath = "$zipPath.sha256"
if ((Test-Path -LiteralPath $zipPath) -or (Test-Path -LiteralPath $checksumPath)) {
    throw "Package already exists: $zipPath. Choose another output folder or increment the app version."
}
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$stagingPath = Join-Path $outputPath ('.staging-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stagingPath | Out-Null
$bundlePath = Join-Path $stagingPath $packageName
New-Item -ItemType Directory -Path $bundlePath | Out-Null

try {
    # Flutter plugins, native assets, and data must travel with the executable.
    # Copy the runtime wholesale so new plugin DLLs are not silently omitted.
    Get-ChildItem -LiteralPath $buildPath -Force | Copy-Item -Destination $bundlePath -Recurse -Force
    $bundleDocs = Join-Path $bundlePath 'docs'
    $bundleImages = Join-Path $bundlePath 'screenshots'
    New-Item -ItemType Directory -Path $bundleDocs, $bundleImages | Out-Null
    Copy-Item -LiteralPath $guidePath -Destination $bundleDocs
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'docs/WINDOWS_RELEASES.md') -Destination $bundleDocs
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'VERIFICATION.md') -Destination $bundlePath
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'server/DEPLOYMENT.md') -Destination $bundleDocs
    # Adapt repository-only deployment links for the downloaded guide.
    $bundledGuide = $guide.Replace('../server/DEPLOYMENT.md', 'DEPLOYMENT.md')
    Set-Content -LiteralPath (Join-Path $bundleDocs 'USER_GUIDE.md') -Value $bundledGuide -Encoding utf8
    foreach ($name in $images) {
        Copy-Item -LiteralPath (Join-Path $repositoryRoot "screenshots/$name") -Destination $bundleImages
    }
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'browser-extension') -Destination $bundlePath -Recurse
    # Ship an applicable project license when the maintainer supplies one.
    Get-ChildItem -LiteralPath $repositoryRoot -File | Where-Object { $_.Name -match '^LICEN[CS]E(?:\..*)?$' } |
        Copy-Item -Destination $bundlePath
    @"
The List $version - Windows x64

Extract this entire ZIP, then run the_list.exe. Keep every DLL and the data folder
beside it. This package has no installer and is not code-signed.

If a Visual C++ runtime is missing, install Microsoft's x64 Redistributable:
https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist

Read docs/USER_GUIDE.md in a Markdown viewer for the illustrated user guide.
The browser-extension folder contains the unpacked Chrome/Edge capture extension.

Your workspace is stored outside this folder; Settings shows its exact location.
Before upgrading, export a backup and close the old app. If the executable moves,
re-enable browser capture and save daily backup settings from its new location.
Sharing needs a reachable connection service; no public service is provisioned.
"@ | Set-Content -LiteralPath (Join-Path $bundlePath 'START-HERE.txt') -Encoding utf8

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    # Finish both files in staging first, so a compression error cannot leave a
    # truncated ZIP with the final release filename.
    $stagedZip = Join-Path $stagingPath "$packageName.zip"
    $stagedChecksum = "$stagedZip.sha256"
    [IO.Compression.ZipFile]::CreateFromDirectory($bundlePath, $stagedZip,
        [IO.Compression.CompressionLevel]::Optimal, $true)
    $hash = (Get-FileHash -LiteralPath $stagedZip -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $packageName.zip" | Set-Content -LiteralPath $stagedChecksum -Encoding ascii
    Move-Item -LiteralPath $stagedZip -Destination $zipPath
    Move-Item -LiteralPath $stagedChecksum -Destination $checksumPath
    if ($env:GITHUB_OUTPUT) {
        "version=$version" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8
    }
    Write-Output "Created $zipPath"
    Write-Output "SHA-256 $hash"
}
finally {
    # Resolve and check the exact generated staging folder before recursive removal.
    $cleanupPath = [IO.Path]::GetFullPath($stagingPath)
    $expectedParent = [IO.Path]::GetFullPath($outputPath)
    if ([IO.Path]::GetDirectoryName($cleanupPath) -cne $expectedParent -or
        [IO.Path]::GetFileName($cleanupPath) -notmatch '^\.staging-[0-9a-f]{32}$') {
        throw "Refusing to remove unexpected staging path: $cleanupPath"
    }
    Remove-Item -LiteralPath $cleanupPath -Recurse -Force
}
