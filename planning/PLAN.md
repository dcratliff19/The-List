# The List development plan

The List is a cross-platform app for collecting project links, descriptions, notes, photos, and reminders, with sharing between friends. This is the original design plan. The native Flutter implementation is now in ../native; see ../README.md and ../VERIFICATION.md for the delivered feature set and tested platforms. Some exploratory interface ideas below, such as QR invitations and a compact list view, remain future options.

## Product and platforms

Target Windows, macOS, Linux, iPhone, iPad, and Android. Interpret Apple as iOS and iPadOS in addition to Mac, and the photo requirement as attaching photos. Recommend installable apps first, with a browser version considered later.

The core journey is to create a project, save a link, describe why it matters, attach a photo or note, set a reminder, and optionally invite a friend. Personal projects should work offline without an account.

## First release features

| Feature | Behavior |
| --- | --- |
| Projects | Create, rename, favorite, archive, choose a color and cover photo, and delete with recovery |
| Links | Store URL, editable title, description, tags, domain, preview image, and saved date |
| Notes | Project notes and contextual notes on links, with simple text editing |
| Photos | Project attachments, optional association with a link or note, captions, and gallery |
| Reminders | Attach a date and time to a project, link, or note; snooze, complete, and show overdue items |
| Friends | Invite trusted people to individual projects and synchronize contributions |
| Search | Search titles, URLs, descriptions, notes, and captions; filter by project, type, and tag |
| Portability | Export and import project archives including attachments |

Defer public profiles, AI summaries, full webpage archiving, browser extensions, recurring reminders, and live collaborative text editing until the core is dependable.

## Visual design

Use a quiet editorial style with warm off-white surfaces, charcoal text, restrained indigo accents, generous spacing, rounded cards, and clear typography. Provide a polished dark theme. Let photos and previews supply most of the color.

Desktop uses a project sidebar, a central collection, and an optional detail pane. Phones use Projects, Reminders, and Search navigation with a prominent Add action. Tablets adapt to available width.

| Screen | Design and actions |
| --- | --- |
| Project library | Cover cards, names, item counts, next reminder, and shared-member avatars |
| Project workspace | Header, search, All / Links / Notes / Photos filters, card or compact list view |
| Item detail | Preview, editable description, tags, reminder, attribution, original link action |
| Quick capture | URL, project picker, description, immediate save while preview loads |
| Reminders | Today, Upcoming, and Overdue groups linked to their content |
| Sharing | Invitation QR or link, members, paired devices, last sync, pending changes |

Example: In Kitchen renovation, save a supplier link, add “Ask whether this comes in matte,” attach a room photo, and set a Saturday reminder. An invited friend can add alternatives.

Design empty, offline, loading, missing-preview, permission-denied, and conflict states. Distinguish “Saved on this device” from confirmed delivery to a friend. Include keyboard navigation, visible focus, screen-reader labels, scalable text, reduced motion, sufficient contrast, and touch targets at least 44 logical pixels.

## Architecture recommendation

Use Flutter and Dart for a shared app. Flutter supports mobile, desktop, and web targets, making it a reasonable fit for the requested platforms and consistent custom interface. Plugin support still needs validation per platform. [Flutter FAQ](https://docs.flutter.dev/resources/faq)

Use SQLite for structured local data, a managed file directory for attachments, and platform secure storage for device secrets. Separate UI, domain rules, repositories, sync, previews, and notifications behind interfaces.

Proposed components are a Flutter app; SQLite storage and full-text search; attachment thumbnails and resumable transfers; authenticated WebRTC data channels; a small signaling service; STUN/TURN connectivity services; and native adapters for notifications, photo pickers, deep links, and sharing into the app.

Select and pin libraries only after testing maintenance, licensing, and actual support on all targets. Apple builds need macOS tooling, and desktop packaging requires appropriate build environments. Plan for Mac hardware or a Mac runner plus Windows and Linux builds. [Flutter setup](https://docs.flutter.dev/install/custom)

## Peer to peer sync

Recommend direct peer connections with encrypted relay fallback. WebRTC uses a separate signaling mechanism and STUN/TURN infrastructure for connectivity across networks. Peer-to-peer therefore does not mean that no servers are needed. [WebRTC peer connections](https://webrtc.org/getting-started/peer-connections)

1. Each installation creates a device identity and stores private keys securely.
2. A project owner generates an expiring, single-use invitation; the friend joins by QR code or link and the owner confirms the device.
3. An established, reviewed cryptographic protocol authenticates peers and grants project access. Do not invent encryption.
4. Devices exchange change summaries, apply missing operations, acknowledge persisted data, and transfer attachment chunks.
5. Disconnections leave edits queued locally; reconnecting resumes safely without duplicate items.

Initially, owners manage membership and invited friends can edit. Pair the user's own devices through the same explicit trust flow. Defer read-only roles and account recovery.

Without hosted storage, a device holding the latest data and its recipient must be online together. TURN forwards traffic but does not provide an offline inbox. Start with this model; offer an optional encrypted store-and-forward mailbox later if asynchronous delivery is needed.

Use foreground and reconnect sync as the baseline. Do not promise continuous background peer sessions on phones; validate allowed background work separately. [Apple background strategies](https://developer.apple.com/documentation/BackgroundTasks/choosing-background-strategies-for-your-app)

Member removal blocks future authorized access and rotates keys for future content, but cannot erase previously received copies. Define membership epochs and reconcile current authorization before accepting or sending edits after reconnection. Keep project content out of service logs.

## Data and conflict handling

| Entity | Main fields |
| --- | --- |
| Project | ID, name, description, color, cover, owner, archive state |
| Item | ID, project ID, type, title, body or description, URL, tags, author |
| Preview | Item ID, fetched title, image reference, domain, timestamp, failure state |
| Attachment | ID, project ID, optional item ID, hash, type, size, caption, availability |
| Reminder | ID, project or item target, due time, time zone, creator, completion |
| Membership | Project ID, device identity, role, authorization epoch, revocation |
| Change | Unique operation ID, entity ID, device, logical revision, payload, deletion marker |

Save each edit and its outgoing change in one database transaction. Apply operations idempotently. Use logical revisions and deterministic tie-breakers rather than trusting device wall clocks. Merge independent fields; retain conflicting versions of prose for user resolution. Keep deletion markers to prevent resurrection by stale devices, and define snapshot resync rules before pruning history.

Test convergence with delayed, reordered, repeated, and interrupted messages. Sync is not a backup: provide versioned exports and test restoration into a clean installation.

## Link previews and photos

Save URLs immediately and fetch metadata asynchronously. Fall back to a domain card when metadata is absent, blocked, or inaccessible. Never overwrite user-written descriptions with fetched text. Do not promise previews for every website.

Fetch only supported HTTP/HTTPS URLs; cap response size, redirects, duration, and image decoding resources. Prevent automatic requests to private or loopback addresses, including redirect and DNS changes. Render extracted text rather than executing page scripts. Allow automatic previews to be disabled for privacy.

Import photos through native pickers and desktop drag-and-drop where supported. Start with JPEG, PNG, and WebP, and validate HEIC conversion before promising it. Propose a 20 MB import limit with clear compression or rejection behavior. Generate thumbnails, transfer metadata ahead of files, and resume interrupted photo transfers. Strip location metadata from shared derivatives by default and clearly explain original retention.

## Reminders

Start with one-time reminders. Store the due instant and intended time zone; specify daylight-saving and travel behavior. Reminders are personal by default even on shared projects, so each friend chooses their own notifications.

Use native scheduling where supported, reconcile after edits, and cancel when the target is deleted. Synchronize completion and snooze across the user's paired devices. Provide per-device notification settings: disconnected devices may both notify before exchanging completion state.

Validate permission denial, app termination, reboot, sleep, and late delivery on every platform. Always retain an in-app due list. If closed-app notifications require a desktop helper, explicitly decide whether to build it before promising equivalent reminder behavior.

## Delivery milestones

These rough estimates assume one experienced full-time developer. Re-estimate after feasibility testing; native integration, security review, device access, and store approval may extend the schedule.

| Phase | Estimate | Exit condition |
| --- | --- | --- |
| Feasibility | 1 to 2 weeks | Two real devices exchange a link and photo across networks; relay fallback works; plugin and notification capability matrix is documented |
| Design and foundation | 1 to 2 weeks | Clickable core flow, light and dark themes, app shell, database, migration strategy |
| Personal app | 2 to 3 weeks | Offline projects, links, notes, previews, photos, search, export/import |
| Reminders | 1 to 2 weeks | Notification and due-list behavior verified against platform lifecycle and time-zone cases |
| Shared projects | 3 to 5 weeks | Invites, authorization, durable queue, conflict recovery, resumable attachments |
| Release preparation | 2 to 3 weeks | Accessibility checks, signed builds, restoration tests, cross-platform pilot |

Working estimate: 10 to 17 developer-weeks for a small beta, not a delivery commitment. Budget separately for signing and store accounts, Mac builds, test devices, signaling hosting, and relay bandwidth. An optional mailbox adds storage costs; obtain current quotes once the beta audience is defined.

## Acceptance criteria

- Create and retrieve projects, links, notes, and photos after restarting offline.
- Failed previews never prevent saving; duplicate URLs provide a clear choice.
- Reminders open the correct target and explain denied or unsupported notification behavior.
- Friends synchronize over direct and relayed connections without data loss after disconnects.
- Concurrent prose edits remain recoverable and peers converge after receiving the same changes.
- Photo transfers resume and reject corrupt chunks while metadata stays usable.
- Expired invitations and revoked devices cannot gain fresh project access.
- Export/import restores metadata and attachments into a clean installation.
- Core flows pass on Windows, macOS, Linux, iPhone, iPad, and Android with appropriate accessibility checks.

## First implementation task

Build a minimal Flutter feasibility prototype that saves a link locally, pairs two devices, exchanges a link and photo, and schedules a reminder. Record the platform matrix and remaining native work. Then implement the project library and quick capture on that validated foundation.
