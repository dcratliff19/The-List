<#
.SYNOPSIS
Publishes a verified Windows package on GitHub after a successful release build.
.DESCRIPTION
Run from the checked-out repository with GitHub CLI authentication. The workflow
provides GH_TOKEN and GH_REPO. Missing tags are created at the exact built commit;
existing drafts are published only after both assets have uploaded successfully.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppVersion,
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$Commit,
    [string]$ArtifactDirectory = 'dist'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($AppVersion -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+\d+)?$' -or
    $Tag -cne ('v' + $AppVersion.Split('+')[0])) {
    throw 'Release tag must match the semantic part of the packaged app version.'
}
if ($Commit -notmatch '^[0-9a-fA-F]{40}$') {
    throw 'Expected the full Git commit SHA used to build the package.'
}

$zipName = "The-List-$AppVersion-Windows-x64.zip"
$zipPath = [IO.Path]::GetFullPath((Join-Path $ArtifactDirectory $zipName))
$checksumPath = "$zipPath.sha256"
foreach ($path in @($zipPath, $checksumPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing release asset: $path"
    }
}
$checksum = ((Get-Content -LiteralPath $checksumPath -Raw).Trim() -split '\s+', 2)
if ($checksum.Count -ne 2 -or $checksum[0] -notmatch '^[0-9a-fA-F]{64}$' -or
    $checksum[1] -cne $zipName -or
    (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash -ine $checksum[0]) {
    throw 'The Windows ZIP does not match its SHA-256 checksum.'
}

# The release job checks out full history/tags. Never label new bytes with an
# existing tag that identifies a different source revision.
$resolvedCommit = & git rev-parse --verify "$Commit^{commit}"
if ($LASTEXITCODE -ne 0) { throw 'The built commit is missing from the checkout.' }
$Commit = $resolvedCommit.Trim()
$tagCommit = & git rev-parse --verify --quiet "refs/tags/$Tag^{commit}"
if ($LASTEXITCODE -eq 0 -and $tagCommit -ine $Commit) {
    throw "Tag $Tag points to another commit. Increment the app version and use a new tag."
}

$assets = @($zipPath, $checksumPath)
$prerelease = $Tag.Contains('-')
$existingJson = & gh release view $Tag --json isDraft 2>$null
if ($LASTEXITCODE -eq 0) {
    $existing = $existingJson | ConvertFrom-Json
    if (-not $existing.isDraft) {
        throw "Release $Tag is already published. Increment the app version to publish another build."
    }
    & gh release upload $Tag @assets --clobber
    if ($LASTEXITCODE -ne 0) { throw 'Release asset upload failed; the draft was not published.' }
    $editArguments = @('release', 'edit', $Tag, '--draft=false', '--target', $Commit,
        "--prerelease=$($prerelease.ToString().ToLowerInvariant())")
    if ($prerelease) { $editArguments += '--latest=false' }
    & gh @editArguments
} else {
    # gh creates the release, uploads its assets, and publishes it. --target
    # creates a missing tag at this commit rather than the default branch head.
    $notesPath = Join-Path $ArtifactDirectory 'release-notes.md'
    $versionNotes = Join-Path $PSScriptRoot "../docs/releases/$Tag.md"
    if (Test-Path -LiteralPath $versionNotes -PathType Leaf) {
        Copy-Item -LiteralPath $versionNotes -Destination $notesPath
    } else {
        @"
Windows x64 build of The List $AppVersion.

Extract the full ZIP and run the_list.exe. Keep all DLLs and data/ beside it.
The ZIP includes the illustrated user guide and browser capture extension.
Install Microsoft's x64 Visual C++ Redistributable if the runtime is missing:
https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist

This folder-based package has no installer, auto-updater, or code signature.
Sharing requires a separately configured connection service.
Export a backup before upgrading; Settings shows the workspace location.
"@ | Set-Content -LiteralPath $notesPath -Encoding utf8
    }
    $createArguments = @('release', 'create', $Tag) + $assets + @(
        '--target', $Commit, '--title', "The List $Tag", '--notes-file', $notesPath
    )
    if ($prerelease) { $createArguments += @('--prerelease', '--latest=false') }
    & gh @createArguments
}
if ($LASTEXITCODE -ne 0) { throw 'Publishing the GitHub release failed.' }
Write-Output "Published The List $Tag with the Windows ZIP and SHA-256 checksum."
