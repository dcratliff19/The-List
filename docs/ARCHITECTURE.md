# Architecture and maintenance

The List is a local-first Flutter application with an optional Node.js signaling
service. SQLite owns project data on each device. The server coordinates peer
connections and stores opaque encrypted offline updates; it never receives the
pairing key or materialized project contents.

## Application boundaries

| Location | Responsibility |
| --- | --- |
| `native/lib/main.dart` | Process startup, workspace directory selection, headless backup mode, and startup failure handling. |
| `native/lib/app/` | Application widget and theme construction. |
| `native/lib/domain/` | Entries, JSON operation types, validation, and search matching. These modules do not open databases or depend on widgets. |
| `native/lib/store.dart` | SQLite ownership, entity queries, local operations, atomic merge/replay, and change notifications. |
| `native/lib/persistence/` | Schema initialization, portable backup/import, and conflict review. |
| `native/lib/project_tools.dart`, `shared_activity.dart` | Store extensions for project planning, personal receipts, and sharing permissions. |
| `native/lib/ui/workspace.dart` | Workspace state, navigation, app lifecycle, capture subscriptions, and service ownership. |
| `native/lib/ui/views/` | Navigation, library, project, board, item, and reminder rendering. |
| `native/lib/ui/editors/` | Project/item editors, reminders, appearance, backup settings, and sharing dialogs. |
| `native/lib/ui/features/` | Planning, comments, organization, capture, Today, activity review, and exports. |
| `native/lib/ui/widgets/` | Reusable presentation and dialog lifecycle helpers. They receive presentation data and callbacks instead of accessing SQL. |
| `native/lib/services/sync/` | HTTP transport, authenticated encryption, bounded frame assembly, peer sessions, WebRTC negotiation, and offline delivery. |
| `native/lib/services/media/` | Public-network preview fetching, address checks, and redirect/response bounds. |
| `native/lib/services/backup/` | Workbook encoding from an immutable export snapshot. |

Private workspace feature extensions are Dart `part` files. They intentionally
share one state owner, including the current project, filters, controllers, and
services. Adding a view does not create another navigation state or another
service lifecycle. Reusable components belong in independently imported widget
libraries; new persistence rules belong in Store APIs, not in UI SQL queries.

The process or test that creates a Store owns its disposal. Workspace owns its
sync, reminder, and backup services, plus its subscriptions and controllers.
Editor controllers remain alive until the dialog route's closing animation
completes. Sync initialization is shared across callers and cannot restore peers
after disposal. `servicesEnabled: false` supports deterministic widget tests.

`PeerSession` depends on the small `PeerHost` interface rather than the secure
storage/pairing implementation. `SignalingClient` accepts a client factory for
transport tests and closes every request's client in a `finally` block.
`MediaService` accepts a `PreviewFetcher` while retaining its existing override
points. Existing imports of `main.dart`, `store.dart`, `services/sync.dart`, and
`services/media.dart` continue to expose their public types.

## Storage and protocol invariants

- Validate an entire operation batch before writing. Merge entity materializations,
  operation history, conflicts, and incoming receipts in one SQLite transaction.
  Publish logical-clock progress and listener notifications only after commit.
- Order field revisions by logical counter, device, and operation ID. Keep replay
  idempotent and enforce project scope and entity identity during merge.
- Keep pairing secrets in OS secure storage. Portable backups retain historical
  attachment references and personal restore data, but exclude pairing keys.
- Treat reminders, read receipts, and access records as device-local state.
  Shared operations and photos must respect the authoritative access role.
- Keep integer minor units for prices. Never combine totals from different currencies.
- Preserve database version 1 and backup version 1. New query indexes are additive.
  Opening a higher database version fails before modifying the schema.
- Preserve direct protocol 3 and accepted offline protocols 2/3. Direct and offline
  messages share the existing AES-GCM envelope (`n`, `c`, `m`) and pairing key.
  Frame assembly checks types, counts, chunk size, and incomplete-message limits
  before decrypting input.
- Resolve and pin public IP addresses for each preview connection, including
  redirects. Keep the fetcher's byte/time limits and image normalization checks.
- Generate workbook and restore data from one frozen snapshot. Verify completed
  backups before retention; preserve unrelated and damaged folders.

## Server boundaries

`server/server.mjs` is the composition root and preserves the
`createSignalingServer(options)` entry point. Importing it does not listen on a
port. Its clock and relay fetch function remain injectable.

| Module in `server/src/` | Responsibility |
| --- | --- |
| `http.mjs` | Bounded JSON object parsing, response headers, and expected request errors. |
| `protocol.mjs`, `limits.mjs` | Credentials, access/signal validation, and resource limits. |
| `room-store.mjs` | Durable credential/mailbox snapshots, expiry, and checkpoint retries. SDP/ICE events remain ephemeral. |
| `ice-provider.mjs` | Cached HTTPS relay responses and time-limited TURN credentials. |
| `rate-limiter.mjs` | Fixed request windows and idle-client cleanup. |
| `mailbox.mjs` | Role-isolated opaque updates, deduplication, byte/count bounds, and acknowledgements. |
| `routes.mjs` | HTTP routing, authentication, room/pairing lifecycle, and protocol responses. |

An asynchronous boundary can change authorization: recheck room existence after
reading mutation bodies or awaiting relay credentials. A guest upload must also
recheck access after its body arrives. Provider failure must neither consume
capacity nor redeem an invitation. Two simultaneous joins may issue only one
guest credential. Expected validation failures produce 4xx responses; internal
failures produce a generic 500 without exposing credentials or filesystem errors.

Room snapshots are written completely to a private temporary file and renamed.
Successful mutations persist immediately; authenticated expiry extensions are
checkpointed. Timers are unreferenced and cleared when the HTTP server closes.
The Dockerfile copies `src/` and runs as the `node` user. There are no runtime npm
dependencies.

## Validation

Run from `native/`:

```sh
dart format --output=none --set-exit-if-changed lib test integration_test tools test_driver
flutter analyze
flutter test --reporter expanded
flutter build windows --release
```

Run from `server/`:

```sh
npm ci --ignore-scripts
npm run format:check
npm test
python ../native/tools/test_linux_reminder.py
```

The native suite covers storage/replay, planning, permissions, receipts, media,
backups, and desktop/phone widget flows. Boundary tests add clock rollback,
future-schema preservation, conflict review, sync initialization disposal,
legacy-envelope compatibility, authentication failures, bounded frame assembly,
and HTTP cleanup. Server tests cover persistence, permissions, mailbox limits,
streaming/revocation races, relay outages, concurrent joins, UTF-8 chunking, and
rate/cache boundaries.

For real native synchronization, start a disposable local server and run:

```sh
flutter test integration_test/sync_test.dart -d windows --dart-define=THE_LIST_TEST_SIGNAL_URL=http://127.0.0.1:PORT
```

Use temporary test workspaces and an isolated endpoint. Platform notification
acceptance remains in `integration_test/reminders_test.dart`. See
[verification notes](../VERIFICATION.md) for checks actually executed and platform
limitations; a Windows result does not establish Apple, Android, or Linux native
acceptance.
