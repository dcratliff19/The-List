$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$publisher = Join-Path $repo 'scripts/publish-windows-release.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('the-list-publication-' + [Guid]::NewGuid().ToString('N'))
$artifacts = Join-Path $fixture 'dist'
New-Item -ItemType Directory -Path $artifacts -Force | Out-Null

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Expect-Rejection([scriptblock]$Action, [string]$Message) {
    try { & $Action } catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw }
        return
    }
    throw "Expected a rejection containing: $Message"
}
function Write-FixtureAssets([string]$Version) {
    $zipName = "The-List-$Version-Windows-x64.zip"
    $zip = Join-Path $artifacts $zipName
    Set-Content -LiteralPath $zip -Value 'Windows release fixture'
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $zipName" | Set-Content -LiteralPath "$zip.sha256"
}
function Reset-Cli([string]$State = 'missing', [string]$Failure = '') {
    $global:releaseState = $State
    $global:failedCommand = $Failure
    $global:releaseCalls = [Collections.Generic.List[object]]::new()
}
# Git runs only against an isolated local fixture. GitHub CLI is fully mocked:
# these checks cannot create, upload, edit, or publish anything on GitHub.
function gh {
    $global:releaseCalls.Add([pscustomobject]@{ Command = $args[1]; Arguments = @($args) })
    $global:LASTEXITCODE = 0
    if ($args[1] -eq 'view') {
        switch ($global:releaseState) {
            'missing' { $global:LASTEXITCODE = 1 }
            'draft' { '{"isDraft":true}' }
            'published' { '{"isDraft":false}' }
        }
    } elseif ($args[1] -eq $global:failedCommand) {
        $global:LASTEXITCODE = 1
    }
}
function Invoke-Publisher([string]$Version = '1.2.0+5', [string]$Tag = 'v1.2.0', [string]$Sha = $script:commit) {
    & $publisher -AppVersion $Version -Tag $Tag -Commit $Sha -ArtifactDirectory $artifacts | Out-Null
}

Push-Location $fixture
try {
    & git init -q
    & git -c user.name=ReleaseTest -c user.email=release-test@example.invalid commit --allow-empty -qm initial
    $script:commit = & git rev-parse HEAD
    Write-FixtureAssets '1.2.0+5'

    Reset-Cli
    Invoke-Publisher
    $create = $global:releaseCalls[1].Arguments
    Assert ($global:releaseCalls[1].Command -eq 'create') 'A manual build must create a release.'
    Assert ($create -notcontains '--draft') 'New releases must be published automatically.'
    Assert ($create[$create.IndexOf('--target') + 1] -eq $script:commit) 'Missing tags must target the built commit.'
    Assert (($create | Where-Object { $_ -match '\.zip(?:\.sha256)?$' }).Count -eq 2) 'Both versioned assets must be attached.'
    Assert ($create -notcontains '--prerelease') 'Stable versions must be normal releases.'

    & git tag v1.2.0 $script:commit
    Reset-Cli
    Invoke-Publisher
    Assert ($global:releaseCalls[1].Command -eq 'create') 'An existing matching tag must allow publication.'

    Reset-Cli draft
    Invoke-Publisher
    Assert ($global:releaseCalls[1].Command -eq 'upload' -and $global:releaseCalls[2].Command -eq 'edit') 'Upload must finish before draft publication.'
    $edit = $global:releaseCalls[2].Arguments
    Assert ($edit -contains '--draft=false' -and $edit -contains '--prerelease=false') 'Stable drafts must become normal published releases.'
    Assert ($edit[$edit.IndexOf('--target') + 1] -eq $script:commit) 'Draft publication must target the built commit.'

    Reset-Cli published
    Expect-Rejection { Invoke-Publisher } 'already published'
    Assert ($global:releaseCalls.Count -eq 1) 'Published releases must not be mutated.'

    Reset-Cli draft upload
    Expect-Rejection { Invoke-Publisher } 'draft was not published'
    Assert ($global:releaseCalls.Count -eq 2) 'Failed uploads must not publish a draft.'
    Reset-Cli missing create
    Expect-Rejection { Invoke-Publisher } 'Publishing the GitHub release failed'
    Reset-Cli draft edit
    Expect-Rejection { Invoke-Publisher } 'Publishing the GitHub release failed'

    Reset-Cli
    Expect-Rejection { Invoke-Publisher -Tag v9.9.9 } 'must match'
    Assert ($global:releaseCalls.Count -eq 0) 'Wrong versions must fail before GitHub access.'
    Expect-Rejection { Invoke-Publisher -Sha short } 'full Git commit'

    $checksumPath = Join-Path $artifacts 'The-List-1.2.0+5-Windows-x64.zip.sha256'
    Remove-Item -LiteralPath $checksumPath
    Expect-Rejection { Invoke-Publisher } 'Missing release asset'
    ('0' * 64 + '  The-List-1.2.0+5-Windows-x64.zip') | Set-Content -LiteralPath $checksumPath
    Expect-Rejection { Invoke-Publisher } 'does not match'
    Write-FixtureAssets '1.2.0+5'

    & git -c user.name=ReleaseTest -c user.email=release-test@example.invalid commit --allow-empty -qm second
    $script:commit = & git rev-parse HEAD
    Reset-Cli
    Expect-Rejection { Invoke-Publisher } 'points to another commit'
    Assert ($global:releaseCalls.Count -eq 0) 'Tag/source mismatch must not access GitHub.'

    & git tag -d v1.2.0 | Out-Null
    & git -c user.name=ReleaseTest -c user.email=release-test@example.invalid tag -a v1.2.0 -m annotated $script:commit
    $tagObject = & git rev-parse refs/tags/v1.2.0
    Reset-Cli
    Invoke-Publisher -Sha $tagObject
    $create = $global:releaseCalls[1].Arguments
    Assert ($create[$create.IndexOf('--target') + 1] -eq $script:commit) 'Annotated tags must resolve to their commit.'

    Write-FixtureAssets '1.3.0-beta.1+6'
    Reset-Cli
    Invoke-Publisher -Version '1.3.0-beta.1+6' -Tag 'v1.3.0-beta.1'
    $create = $global:releaseCalls[1].Arguments
    Assert ($create -contains '--prerelease' -and $create -contains '--latest=false') 'Prereleases must not become Latest.'
    Reset-Cli draft
    Invoke-Publisher -Version '1.3.0-beta.1+6' -Tag 'v1.3.0-beta.1'
    $edit = $global:releaseCalls[2].Arguments
    Assert ($edit -contains '--prerelease=true' -and $edit -contains '--latest=false') 'Draft prereleases must keep prerelease status.'

    Write-FixtureAssets '1.2.1+6'
    Reset-Cli
    Invoke-Publisher -Version '1.2.1+6' -Tag 'v1.2.1'
    $notesPath = Join-Path $artifacts 'release-notes.md'
    $expectedNotes = Get-Content -LiteralPath (Join-Path $repo 'docs/releases/v1.2.1.md') -Raw
    Assert ((Get-Content -LiteralPath $notesPath -Raw) -ceq $expectedNotes) 'Version-specific release notes must be attached unchanged.'
    Assert ($global:releaseCalls[1].Arguments -contains $notesPath) 'Release creation must use the prepared notes file.'
}
finally {
    Pop-Location
    $cleanupPath = [IO.Path]::GetFullPath($fixture)
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ([IO.Path]::GetDirectoryName($cleanupPath) -ine $temporaryRoot -or
        [IO.Path]::GetFileName($cleanupPath) -notmatch '^the-list-publication-[0-9a-f]{32}$') {
        throw 'Refusing to remove an unexpected publication fixture.'
    }
    Remove-Item -LiteralPath $cleanupPath -Recurse -Force
}
Write-Output 'Passed 16 publication cases with real local Git tags and mocked GitHub CLI; no remote changes.'
