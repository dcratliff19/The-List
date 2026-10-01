# Verification — 30 September 2026

Flutter 3.47.5 / Dart 3.13.4 on Windows. Native implementation in `native/`.

## CI failure fixes — Linux/macOS widget fonts and Windows compiler

The reported GitHub test summary contained five failing widget cases. Reproduced
all five on Linux under WSL with the original font helper: the first exceptions
were RenderFlex overflows of 66 and 79 pixels. The helper loaded a real text font
only on Windows; Linux and macOS widget tests used Flutter's fixed-width Ahem
font with their default Android/Roboto typography.

`native/test/helpers/fonts.dart` now loads the bundled Noto Sans font as Roboto
on every host and obtains font/icon assets from the asset bundle. Windows keeps
its Segoe UI font for existing screenshot metrics. The new font fixture regression
checks that equal-length narrow/wide strings have proportional glyph widths.

The reported Windows compilation used Visual Studio 18 / MSVC 14.51 and failed
with STL1011 in the notification plugin's C++/WinRT headers. Added Microsoft's
documented compatibility definition only to that vendored plugin's CMake target.
Both Windows workflows now use `windows-2022` rather than a moving compiler
image. The plugin retains C++17 for compatibility with older SDK headers; its
coroutine migration needs a coordinated future SDK/plugin update. See
[Microsoft's C++/WinRT issue](https://github.com/microsoft/cppwinrt/issues/1520).

Both workflows use `flutter test --reporter expanded` to preserve exceptions and
stack traces in future CI logs.

| Verification | Result |
| --- | --- |
| Original Linux widget cases | All five reproduced as failures using the original helper in an isolated source copy. |
| Fixed Linux suite | All 35 tests passed with Flutter 3.47.5 / Dart 3.13.4 under WSL. |
| Fixed Windows suite | All 35 tests passed. |
| App analysis | No issues found. |
| Windows release | Rebuilt successfully with Visual Studio 2022; generated plugin project includes the compatibility definition. |
| Workflow checks | Both workflows passed actionlint and Prettier. |

The isolated Linux helper was restored after the reproduction. No app data was
used in these checks. macOS execution and the updated GitHub-hosted builds still
need a fresh run after the changes are pushed. The local Windows compiler is
Visual Studio 2022; Visual Studio 18 was not available for a local compilation.

## GitHub documentation and Windows release packaging

Prepared a GitHub-facing README, a roughly 4,500-word user guide with 12 actual
app/widget screenshots and captions, and maintainer release instructions. Guide
images use sample projects; unrelated screenshots are not bundled in releases.
Validated 46 local documentation links, image references, and heading anchors.

Added a dedicated Windows release workflow: manual or `v*` tag triggers, locked
dependencies, formatting/analysis/tests, x64 compilation, full-runtime ZIP and
SHA-256 packaging, and a separate tag-only draft-release job. Tags must match the
semantic version in pubspec. General native CI continues on branch pushes, pull
requests, and manual runs without duplicating the tag release build.

| Check | Result |
| --- | --- |
| Locked Flutter dependency resolution | `flutter pub get --enforce-lockfile` succeeded. |
| Windows release compilation | `flutter build windows --release --no-pub` succeeded after the source cleanup. |
| Packaging | Versioned `1.2.0+5` x64 ZIP created in ignored `dist/`; 23 runtime files preserved byte-for-byte, including all DLLs and data. |
| Guide distribution | All 12 guide images, browser extension, guide and related notes included; bundled guide links resolve. |
| Archive integrity | ZIP CRC checks and the external SHA-256 checksum passed. |
| Workflow validation | Both workflows passed actionlint 1.7.12; all 8 run scripts plus the packaging script parsed as PowerShell. |
| Release safeguards | Five packaging rejection cases passed: wrong tag, missing runtime, output outside checkout, output inside runtime, and existing package. Existing package remained unchanged; temporary staging was cleaned. |
| Bundled endpoint | Six mocked build cases passed: empty/valid endpoint accepted, HTTP/credentials/query/fragment rejected. |
| Draft release | Four mocked CLI cases passed: create draft, refresh existing draft, refuse published release, surface failed creation. No GitHub mutation performed locally. |
| Formatting | README, guide, release instructions, workflows, and the existing server formatting check passed Prettier. |

The local release executable is unsigned. There is no Git metadata or configured
GitHub repository in this checkout, so the workflows have not executed on GitHub
and no release has been published. Hosted runner compilation, actual artifact
delivery, and GitHub draft creation remain remote checks after pushing the source.
The fresh package in `dist/` does not replace older local `releases/` packages.

## Code review and cleanup — latest source

Reviewed maintained application code, sync/storage/exports, the signaling service,
browser capture, platform capture/reminder helpers, tests, and build configuration.
Generated platform files, packaged releases, upstream vendor implementations, and
the archived web design scaffold were not reformatted. The local Windows plugin
patches were inspected as part of native build verification.

### Fixed findings

| Area | Finding and resulting change | Verification |
| --- | --- | --- |
| Portable backups | Only current photos were exported. Exports now include available photos referenced by earlier revisions, so photo history remains recoverable after import. | Historical-photo round-trip regression. |
| Project exports | Excel/PDF could read newer live records after the portable snapshot was captured. All export formats now materialize one frozen operation snapshot, disposing the temporary database reliably. | Snapshot consistency regression and existing Excel/PDF tests. |
| Capture URLs | Repeated query values were collapsed, changing URLs and duplicate decisions. Normalization preserves value lists and sorts only parameter keys. | Repeated-value and encoded-delimiter regression. |
| Personal reminders | The global menu dereferenced a missing selected project and incorrectly applied shared editing permissions to personal actions. Snooze/edit/delete work without a selected project, including read-only projects. | Read-only global-reminder widget regression. |
| Read-only capture | The capture destination could refer to a project absent from its editable choices. Capture now defaults to the private Inbox when browsing a read-only project. | Capture-review widget regression. |
| Editor lifecycle | Several dialogs leaked text controllers or disposed them before route animations finished. A shared dialog helper releases controllers after route completion; asynchronous picker callbacks check that their dialog is mounted. | Existing editor/desktop/phone widget flows. |
| Invitations | Relay-provider failure could consume an invitation or leave an orphan room. Relay lookup now precedes mutation, with invitation/capacity rechecks after awaits. Expiry is enforced at the exact deadline. | Provider-outage and concurrent-join regressions, plus expiry tests. |
| Signaling input | UTF-8 split across TCP chunks could be corrupted; loosely validated signals could inflate response queues. Bodies decode once, signal fields are validated, retained signals have a byte limit, and malformed objects/routes/cursors receive explicit errors. Oversized requests return HTTP 413. | Split-UTF-8, validation, body-limit, and bounded-response regressions. |
| Offline access | A guest upload started before a downgrade could bypass the earlier access check. Upload permission is checked after the request body is read. Mailbox accounting measures bytes and encoded response size. | Server access regressions and native offline-delivery integration. |
| Linux reminders | A stale timer could deliver after notifications were disabled. The helper now rechecks the setting and target's project before delivery. | Mocked Linux-helper tests for disabled settings and cross-project targets. |
| Supporting code | Icon generation no longer runs on module import. Browser capture handles query failures and announces status accessibly. Repeated widget font setup is shared; normal Excel tests no longer write screenshot artifacts. | Python/JavaScript syntax checks and widget suite. |

### Maintenance changes

- Dart sources, tests, integration tests, and tools use the SDK formatter. JavaScript,
  HTML, JSON, and workflow files use pinned Prettier 3.5.3 as a development dependency.
- Root EditorConfig/Prettier configuration and `server/package-lock.json` make
  formatting reproducible. CI now checks formatting and the Linux reminder helper.
- Comments explain field convergence, local receipts, permission authority, network
  address pinning, export snapshots, controller ownership, and platform capture queues.
- The Windows integration accepts an isolated signaling endpoint through
  `THE_LIST_TEST_SIGNAL_URL`. This review used an ephemeral port and temporary test
  workspaces; the existing Docker service, pairing volume, and user database were not changed.
- This supplied workspace has no Git metadata. Pre-cleanup source is saved in
  `.review-backup/source-before-cleanup.zip`; that local recovery directory is ignored.

### Verification for this cleanup

- Dart formatting check: 33 maintained Dart files, no changes required.
- Prettier formatting check and JavaScript syntax checks pass.
- Flutter analysis: no issues. All 34 unit/widget tests pass.
- Signaling service: all 12 tests pass, including an in-flight upload downgrade.
- Linux reminder helper: all 5 mocked tests and Python syntax checks pass.
- Windows debug build and real native WebRTC integration pass against the updated
  isolated Node server, including read-only access, edits, comments, photos,
  reconnection, and encrypted offline delivery.

- Android debug APK compiles successfully. Gradle still reports an upstream
  Kotlin Gradle Plugin migration warning for `file_picker` and `flutter_webrtc`;
  dependency migration was not part of this source cleanup.

Apple/Linux compilation and live browser-extension activation remain platform
acceptance checks. Existing release packages were not regenerated by this source
cleanup. The remaining sections document earlier verification runs.

## Passed

- `flutter analyze`: no issues.
- `flutter test`: 8 tests covering persistent SQLite storage, idempotent merge, concurrent field convergence, conflicting note history, deletion/recovery, transaction rejection, backup integrity, private-network preview rejection, and desktop/mobile editing.
- `node --test server.test.mjs`: 3 signaling tests covering authorization, signal isolation, single-use and expired invitations, revocation, active-session expiry, and relay credential refresh.
- Windows native WebRTC integration: two independent stores, secure pairing persistence, encrypted operations, simultaneous edits, chunked photo transfer with byte equality, offline edits after reconnect, deletion, and disconnection.
- Windows native notifications integration: an OS scheduled notification appears in pending requests and disappears when its reminder is completed.
- Android emulator integration: native app loads, example project opens, a note is created and saved in SQLite, and phone layout has no Flutter overflow/exception. Screenshots 06–07 came from this running emulator.
- Linux helper logic: 3 Python tests cover notification target arguments, completed/deleted/future reminders, and deleted parent content. Desktop notifications are mocked in these helper tests.

## Build and distribution scope

Windows and Android release artifacts are supplied in `releases/`. Android uses development signing for direct installation. Windows is a portable unsigned application; extract the complete folder. Neither is an app-store release.

macOS, iOS/iPadOS, and Linux platform projects are included, with a GitHub Actions build matrix. These targets have not been compiled or exercised on their respective operating systems here. Apple distribution requires a developer team and signing/provisioning. Linux systemd and desktop delivery need an on-device test. The workflow has not been run in GitHub.

The Android integration test exercises the UI and local storage; Android notification permissions and cross-device WebRTC still need a real-device acceptance pass. Windows notification scheduling/cancellation was tested, not every closed-app click-through scenario.

The HTTPS/Caddy/coturn deployment is configured but not deployed. The native WebRTC test used two peers on this workstation and a local signaling service. External NAT traversal, TURN-only connectivity, and internet deployment need an acceptance test on separate networks.

## Reproduction

From `native/`:

```sh
flutter pub get
flutter analyze
flutter test
flutter test integration_test/sync_test.dart -d windows
flutter test integration_test/reminders_test.dart -d windows
flutter drive --driver=test_driver/screenshots.dart --target=integration_test/android_test.dart -d emulator-5554
python tools/test_linux_reminder.py
```

Start `node server/server.mjs` first for the sync test. Run Flutter test/build commands sequentially in a single checkout because generated platform plugin registration is shared.

Android screenshots are written to `screenshots/`. Flutter-rendered screenshots 01–03 can be refreshed with `flutter test --update-goldens` on Windows. Screenshots are not used as date-sensitive pixel assertions in the normal suite.

## Known operating boundaries

Direct sync requires both peers online. Version 1.1.0 adds opt-in encrypted text delivery through the server mailbox; photos still wait for direct sync. Pairing secrets are held in OS secure storage; workspace records and photo files use normal OS account/disk protection. Shared peers receive a copy with read-only or update access; disconnecting does not erase their copy. Reminders are personal and do not sync.

Preview fetching is best-effort; sites that require JavaScript/authentication or prohibit extraction retain a usable link without a preview. JPEG/PNG/WebP photos are normalized and EXIF is removed. See the main guide for limits and backup behavior.

## 1.0.1 update

Fixed HTTPS preview transport by wrapping the pinned TCP connection with verified TLS and the original hostname. Live checks against dart.dev and Magpul returned titles and preview images. Added four preview regressions; the full suite now has 12 tests. Native Windows WebRTC integration passes after automatic reconnect changes. Server suite now has four tests, including persisted pairing credentials across restart and revocation.

Share no longer asks each friend for a server address. The app supports a bundled THE_LIST_SIGNAL_URL, a one-time connection setting, persistent central pairing state, and a server-side managed ICE provider. A production service still requires a domain/host or provider account; none was deployed in this session.
# Local Docker verification — 2026-09-30

- `compose.local.yaml` deployed as `the-list-signal-1`; Docker health check passes at `http://127.0.0.1:5174/health`.
- Native Windows WebRTC integration test passed against Docker: edits, photos, concurrent changes, disconnect and reconnect.
- A disposable paired client retained authenticated access after an actual container restart; test pairing removed afterward.
- Real native link preview screenshot: `screenshots/10-working-link-preview.jpg`.
- Local Docker binds to loopback. Public HTTPS and TURN deployment remain necessary for friends on other networks and have not been verified publicly.

## 1.1.0 expansion — 2026-09-30

- Static analysis: no issues. Windows and Android 1.1.0 release builds succeeded. App unit/widget suite: 23 passing tests, including manual board membership, custom columns and ordering, explicit purchase totals, normalized duplicates, inbox moves, recurrence, competing revision preservation, selective restore, retention and corruption detection, long-note PDF pagination, and desktop/phone UI flows.
- Server suite: 5 passing tests, including mailbox authentication, recipient isolation, idempotency, restart persistence, acknowledgements, size limits and expiration.
- Windows native integration passed against the identical Node service: real WebRTC edits/photos/reconnection/deletion, then both channels closed and encrypted offline text delivered. Personal reminders did not transfer.
- Flutter-rendered screenshots 17–22 use isolated fixture data. No new sample data was added to the user's workspace.
- The user recovered Docker Desktop startup. Updated `the-list-signal-1` is healthy at loopback port 5174 with the existing pairing volume. The full Windows native sync test then passed against Docker, including encrypted offline delivery. The temporary Node process was stopped. No containers or data volumes were reset.
- iOS ShareExtension source and a Mac target-setup script are included. Xcode compilation, App Group provisioning, signing and device validation remain unverified. macOS/Linux native compilation, browser-extension activation on those systems, and public-network TURN acceptance remain unverified.

- Packaged Windows app launched successfully with the existing user workspace (AP5SD build and A space of our own). Live project-tools screenshot: 24-windows-release-tools.jpg.
- Android 1.1.0 APK installed on the API 36.1 emulator. A real ACTION_SEND text intent opened Quick capture with the URL populated and no automatic save. The headless emulator needed software rendering; screenshot 23-android-share-capture.png verifies the resulting app screen.

## 1.1.1 project and item comment Inbox

- 25 unit/widget tests pass. New coverage checks three-device relaying, equal display names, sender exclusion, duplicate suppression, read/unread persistence after restart, deleted targets, backup restoration, composing project comments and opening their conversation from Inbox.
- Static analysis reports no issues.
- The real native Windows sync integration passes against the existing healthy Docker server, including live project comments, list-item replies and offline encrypted comment delivery. Existing read state remains unchanged.
- Comment receipts/read flags are local SQLite state and are not sent to other participants. Recipient identity is device-based; this release does not introduce user accounts or link the same person's multiple devices.

- Windows and Android 1.1.1 release packages built and published to releases/. Android plugin registration was regenerated after integration testing before the successful release build.


## 1.2.0 shared activity and permissions

- Full unit/widget suite: 28 passing tests. Feed coverage includes received changes in both directions, three-device relaying, own-device exclusion, duplicate suppression, preview housekeeping exclusion, deletion events, persistent unread state, opening items, and desktop/phone layouts.
- Read-only checks cover local edits, additions, comments, restore attempts and forged direct messages. Personal reminders remain available. Regression coverage ensures an older secure pairing snapshot cannot override a newer SQLite access decision after restart.
- Server suite: 6 passing tests. Read-only invitations remain read-only even if a joining guest requests update access. Guests cannot change their access or upload mailbox updates. Owners can grant update access and revoke it; revocation removes pending guest mailbox uploads.
- The native Windows WebRTC test against Docker verifies read-only reception, granting update access, editor changes appearing in the owner's feed, downgrading, comments, photos, reconnection, and encrypted offline receipt while read-only.
- Screenshots 27–30 show actual Flutter widget renders with isolated test data. No sample projects were added to the user's database.
- The existing Docker service was rebuilt with its pairing volume preserved and reports healthy. Public deployment and Apple/Linux device validation remain outside the locally verified platforms.

- Final Windows and Android 1.2.0+5 release builds succeeded. Latest Windows folder/ZIP and Android APK were replaced, and SHA256SUMS.txt regenerated. The normal launcher points to the updated Windows folder. Final desktop/phone feed and sharing screenshots were refreshed successfully.
