# Changelog

## 1.2.1 — 2 October 2026

- Refactored the app and signaling service into focused modules for UI, storage,
  synchronization, media, backups, and server request handling.
- Added typed navigation, reusable UI components, testable HTTP/encryption
  boundaries, and architecture documentation.
- Fixed logical-clock rollback on failed database batches and protected newer
  database schemas from accidental modification.
- Prevented peer restoration after disposal, tightened frame validation, and
  rechecked revocation during streamed requests and relay lookups.
- Added indexed project queries and kept SQL behind the Store API.
- Expanded regression coverage to 47 app tests and 20 server tests; verified
  real Windows WebRTC/offline synchronization and the server container.
- Added server checks and publication regression tests to the Windows release
  workflow, version-label validation, and version-specific release notes.

Existing database, portable backup, and sharing protocol formats remain compatible.

## 1.2.0

Initial GitHub Windows release with project planning, links, notes, photos,
reminders, browser capture, encrypted sharing, conflict review, and portable,
Excel, and PDF exports.
