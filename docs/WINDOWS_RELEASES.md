# Windows release builds

The dedicated workflow is `.github/workflows/windows-release.yml`. It builds an x64 Windows release, checks the app, and packages everything needed to run it. The version is read from `native/pubspec.yaml`; it is not inferred from a filename or manually entered during the build.

## What a run produces

For `version: 1.2.1+6`, the outputs are:

```text
dist/
  The-List-1.2.1+6-Windows-x64.zip
  The-List-1.2.1+6-Windows-x64.zip.sha256
```

The ZIP has one application folder containing `the_list.exe`, all release DLLs/native assets, `data/`, `START-HERE.txt`, the illustrated guide and its sample screenshots, and the browser extension. It also includes the changelog, architecture/deployment/verification notes, and a root license file if the repository supplies one. It does not include a user's workspace, pairing keys, unrelated screenshots, or the signaling service executable.

This is a folder-based package, without an installer, code signature, or automatic updater. Users extract the whole folder. Machines missing the Microsoft C++ runtime need the [x64 Redistributable](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist). Add signing and installer infrastructure separately before describing a release as signed or installed.

## Run a build manually

1. Push the project to a GitHub repository, including `native/pubspec.lock`, `native/vendor/`, documentation, screenshots, and `scripts/`. Do not commit local data or signing credentials.
2. Ensure Actions is enabled and the workflow exists on the default branch.
3. Set an unused semantic version in `native/pubspec.yaml`, commit/push it, then open **Actions → Windows release → Run workflow** and select that branch.
4. After a successful run, open **Releases** to download the automatically published Windows ZIP and checksum. The version tag is created at the exact commit built by the workflow when it does not exist yet.

A manual run publishes automatically after the build, tests, and packaging succeed; there is no draft approval step. A version such as `1.2.1+6` produces release `v1.2.1`. Existing tags must identify the built commit, and published releases are not overwritten. Increment the semantic version for another release; changing only the `+` build number does not produce a new release tag.

For this manual flow, do not create a release or tag in GitHub first. The workflow creates both after the checks pass. Git can also create and push a tag without a release, using the commands below. If you use GitHub's release editor instead, save a draft and then run the workflow manually; publishing the release first makes the publisher reject that version as already published.

The **The-List-Windows-x64** artifact is also available from the run for 30 days, subject to repository/organization limits. Extract that artifact's wrapper ZIP to find the application ZIP and checksum. General **Native builds** remains a CI workflow that uploads artifacts; use **Windows release** to publish.

The release first checks server formatting/tests, extension syntax, and the Linux reminder helper on Node 22/Linux. The Windows build then runs locked dependency resolution, mocked publication/SQLite safeguard tests, Dart formatting checks, `flutter analyze`, `flutter test --reporter expanded`, and `flutter build windows --release --no-pub`. Packaging fails if required runtime files or guide images are missing, or the Settings version label differs from the manifest. The workflow pins Flutter 3.47.5 and GitHub's `windows-2022` runner with Visual Studio 2022. Update these choices consistently with `.github/workflows/build.yml` when changing toolchains.

The vendored Windows notification plugin uses C++17 and SDK-provided C++/WinRT headers. It has a plugin-only compatibility definition for the experimental coroutine deprecation error introduced in MSVC 14.51. This preserves compatibility with older SDK headers; migration to standard coroutines needs a coordinated SDK/plugin update. Both workflows use expanded test output so future failures include the exception and stack trace.

Both Windows workflows run `scripts/prepare-sqlite-windows.ps1` after dependency resolution. It reads the installed, locked SQLite package's release tag and Windows x64 SHA-256 hash, downloads from that upstream release with HTTP error handling and bounded retries, and seeds Flutter's native-hook cache only after the checksum matches. The SQLite hook verifies that cache again. This avoids treating a failed download response as a DLL; hash verification remains enabled. The cache layout is tied to the pinned Flutter/Dart toolchain and should be checked when upgrading it.

If **Test the app** reports a SQLite DLL hash mismatch before any tests run, that is a native-asset download failure, not a tag/release collision. Inspect the **Prepare verified SQLite runtime** step for HTTP or checksum errors. A persistent mismatch stops the build rather than accepting unexpected bytes.

## Prepare a tagged release

1. Set the intended version in `native/pubspec.yaml`, update the user-facing version labels if needed, and commit the finished changes. Perform local checks before pushing the release tag; successful manual Windows release runs also publish.
2. Create and push an annotated tag matching the semantic part of the app version. For `1.2.1+6`, use `v1.2.1`:

   ```sh
   git tag -a v1.2.1 -m "The List 1.2.1"
   git push origin v1.2.1
   ```

   Use the version you are actually releasing; the commands above are an example. A tag such as `v1.2.2` fails when pubspec still says `1.2.1+6`. A prerelease such as `1.3.0-beta.1+6` uses `v1.3.0-beta.1`.

3. The tag starts **Windows release**. General **Native builds** runs on branch pushes, pull requests, and manual runs; tag packaging is handled by this dedicated workflow.
4. After the build succeeds, a separate job **publishes** the release with its Windows ZIP and SHA-256 checksum. Its write permission is limited to that job, using the repository's `GITHUB_TOKEN`; no separate personal access token is required.
5. Versions with a prerelease suffix, such as `1.3.0-beta.1+6`, publish as prereleases and are not marked Latest. Stable versions publish as normal releases. For a new release, the publisher uses `docs/releases/<tag>.md` when supplied, otherwise generic installation notes. Version-specific notes for `v1.2.1` are included in this checkout.

An existing draft can be completed automatically: assets are uploaded before publication. If upload fails, the draft stays unpublished. The publisher verifies the ZIP checksum and rejects a tag pointing to another commit or an already published release. Publication jobs for the same release tag are serialized. Do not move a published version tag or substitute different bytes for it; increment the semantic app version and use a new tag.

Organization policies can restrict Actions, tag creation, or token write access. If publishing fails for that reason, the build artifact remains available; resolve the repository policy or attach the verified ZIP/checksum to a release manually.

## Optional bundled sharing address

To provide a default connection service, set a repository Actions **variable** named `THE_LIST_SIGNAL_URL` under **Settings → Secrets and variables → Actions → Variables**, such as `https://list.example.org`. The workflow passes it as a Flutter compile-time definition.

The value must be an HTTPS URL without credentials, a query, or a fragment. It is a public endpoint embedded in the app, not a secret. Do not put invitation keys or service credentials there. With no variable, the app is built without a bundled service; users configure one in Settings. A per-installation configured address takes precedence over the bundled default.

Building the app does not deploy this service or configure TURN. Follow the server deployment guide in the source repository; recipients need a reachable service and matching permission-aware app/server versions.

## Compile and package locally

On Windows, install Flutter 3.47.5 and Visual Studio's **Desktop development with C++** workload. From the repository root:

```powershell
Push-Location native
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test integration_test tools test_driver
flutter analyze
flutter test
flutter build windows --release --no-pub
Pop-Location

./scripts/package-windows.ps1
```

Check each command's result before proceeding. The packaging script reads `native/build/windows/x64/runner/Release` by default. It copies the runtime wholesale so additional plugin DLLs are included automatically.

Optional script arguments:

```powershell
# Check a tag against the app manifest without compiling or packaging.
./scripts/package-windows.ps1 -Tag v1.2.1 -ValidateOnly

# Use another output directory inside this checkout for a repeated local build.
./scripts/package-windows.ps1 -OutputDirectory ./dist/local-check
```

`-BuildDirectory` may point to another complete release folder inside the checkout. Output/staging paths must also stay inside the repository. Existing output files are not overwritten; choose another output directory or increment the version. Temporary staging is removed after packaging, and generated `dist/` is ignored by Git. Existing local `releases/` packages are not changed.

The repository contains a launcher intended for an older local `releases/` layout. The new ZIP does not depend on it: launch the executable inside the versioned package directly.

## Verify a download

Put the application ZIP and its `.sha256` companion in the same folder. For the example version, use PowerShell:

```powershell
$zip = './The-List-1.2.1+6-Windows-x64.zip'
$expected = ((Get-Content -LiteralPath "$zip.sha256" -Raw).Trim() -split '\s+')[0]
$actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
if ($actual -ine $expected) { throw 'The ZIP checksum does not match.' }
```

The checksum detects changed or incomplete bytes. It is not a code signature and does not authenticate a download independently of the source hosting both files.

## Other platform setup

The general workflow builds Android, Linux, macOS, and unsigned iOS outputs as well. Those are not packaged by the Windows release workflow.

For iPhone share extension setup on a Mac with Xcode and the CocoaPods-provided `xcodeproj` Ruby gem:

```sh
cd native/ios
ruby setup_share_extension.rb YOUR_TEAM_ID app.yourname.thelist
```

The script creates/configures the extension target. In Xcode, give Runner and ShareExtension the same App Group, `group.app.yourname.thelist.shared`, and select your signing team. Your signing account must support the App Group provisioning. The extension queues incoming links for review on the next app open. This source still needs Mac compilation and iPhone device validation; Windows release success does not verify it.

For Linux capture registration, run `sh native/linux/install-capture.sh /absolute/path/to/the_list` from the source root. Android registers as a text/link share target. macOS registers its capture scheme through its app bundle. See the source verification notes for platform-specific outstanding checks.

## Reference documentation

- [Flutter Windows setup](https://docs.flutter.dev/platform-integration/windows/setup)
- [Flutter Windows build and distribution](https://docs.flutter.dev/platform-integration/windows/building)
- [Flutter's architecture-specific Windows output paths](https://docs.flutter.dev/release/breaking-changes/windows-build-architecture)
- [Flutter setup action](https://github.com/subosito/flutter-action)
- [GitHub workflow syntax and token permissions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
- [GitHub artifact upload action](https://github.com/actions/upload-artifact)
- [GitHub CLI release creation](https://cli.github.com/manual/gh_release_create)
- [GitHub CLI draft publication](https://cli.github.com/manual/gh_release_edit)
