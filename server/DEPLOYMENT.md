# Sharing service deployment

The List's Node server handles introductions and temporary SDP/ICE messages. Project operations and photos travel through encrypted WebRTC data channels. TURN is a connectivity relay. The optional authenticated mailbox separately stores encrypted updates for asynchronous delivery.

## Local use

For the local Docker server, run `docker compose -p the-list -f compose.local.yaml up -d --build` from this directory. It exposes `http://127.0.0.1:5174`, checks server health, restarts automatically, and persists pairings in a named volume. This address is for apps on this computer; use the HTTPS deployment below for friends on other devices. Check status with `docker compose -p the-list -f compose.local.yaml ps`.

Run `node server.mjs`. The default endpoint is `http://127.0.0.1:5174`. The Android emulator reaches the host at `10.0.2.2`; use HTTPS for normal remote clients.

Run `node --test server.test.mjs` for invitation expiry, single use, authorization, and signal-isolation checks.

## HTTPS and TURN on a Linux host

1. Point a DNS name for signaling and another for TURN to your server.
2. Copy `.env.example` to `.env`, set the domain/IP values, and generate a long random TURN shared secret. Keep it out of source control.
3. Review firewall rules: TCP 80/443 for Caddy, UDP/TCP 3478 for TURN, and UDP 49160–49200 for relayed media/data.
4. Run `docker compose up -d --build`.
5. Confirm `https://YOUR_SIGNAL_DOMAIN/health` returns `ok: true` and `relayConfigured: true`.
6. Enter that HTTPS origin in the app's Share dialog. Create an invitation and connect a second device on a different network. Test a restrictive network as well as a direct connection.

The sample Compose file assumes a Linux host with a public IPv4 address. coturn uses host networking. Adjust NAT/external-IP settings if deployed behind another router. The app receives one-hour TURN credentials derived from the shared secret; it never receives the server secret.

The service limits request sizes, requests per IP, room count, and retained signals. It is designed for a small trusted group. Apply hosting-level bandwidth limits and monitoring before allowing broad public use; TURN bandwidth is the main operating cost. If placing the app behind an additional authentication gateway, adapt client authentication as well.

With STATE_FILE configured, pairing state survives restarts. Inactive pairings expire after 90 days; new invitations expire after 15 minutes and can be redeemed once. Without STATE_FILE, room state remains in memory only. No project data is lost when room state expires.

## Service environment

- `HOST`: bind address, default 127.0.0.1.
- `PORT`: default 5174.
- `TURN_URLS`: comma-separated TURN URLs.
- `TURN_SECRET`: matches coturn's static authentication secret.

The server does not log bearer tokens, invitations, SDP, or project data. HTTPS protects connection signaling; AES-GCM and WebRTC DTLS protect project content. Anyone who receives an invitation can join its project, so users should share invitations only with intended friends.

The Docker deployment and external TURN fallback are configured but were not deployed or exercised against a public network in this session.

## Seamless app distribution (1.0.1)

The app owner configures one public HTTPS signaling origin when building the apps:

```sh
flutter build windows --release --dart-define=THE_LIST_SIGNAL_URL=https://YOUR_SIGNAL_DOMAIN
flutter build apk --release --dart-define=THE_LIST_SIGNAL_URL=https://YOUR_SIGNAL_DOMAIN
```

The same define works for macOS, Linux, and iOS builds. For local development, set the process environment variable THE_LIST_SIGNAL_URL or use Settings → Connection settings once. Normal Share has no server field; recipients receive connection information in their invitation.

No production domain is embedded until you supply it. A release with no bundled origin allows a one-time installation setting. Never embed localhost in a public release.

The Compose deployment persists hashed pairing credentials in its signal_state volume. Paired sessions expire after 90 days without activity. Invitations are still single use and expire after 15 minutes. Do not delete the state volume during upgrades. Raw bearer tokens and project encryption keys are never written by this server.

STATE_FILE enables persistence outside Docker. Keep that file private and backed up. TRUST_PROXY=true is for the included reverse-proxy deployment only; do not enable it on a publicly exposed Node port.

### Managed TURN alternative

Set ICE_SERVERS_URL on the server to your provider's HTTPS ICE-credentials API endpoint (for example, Metered/Open Relay). The server fetches and briefly caches the response; users receive only the temporary ICE configuration, never the API endpoint or API key. Keep this URL in server secrets, not the app or source control.

This replaces coturn credential generation when configured. Metered currently advertises a free 20 GB monthly TURN allowance and requires an account: https://www.metered.ca/tools/openrelay/

PeerJS Cloud offers free signaling, but speaks PeerJS's protocol; it is not a drop-in endpoint for this app's authenticated signaling API. Avoid treating public STUN servers as a complete sharing service: they do not provide signaling or guarantee a relay path.

### What remains a deployment step

Provide a domain and host (or provider account), deploy the service, and test two devices on different networks. Both peers must be online at the same time for direct synchronization. A central signaling service does not itself store offline project changes.

For the managed relay deployment, set SIGNAL_DOMAIN and ICE_SERVERS_URL in .env, then run `docker compose -f compose.managed.yaml up -d --build`. This runs your own signaling service and Caddy without coturn. The standard compose.yaml continues to use your own coturn relay.

## Encrypted mailbox (1.1.0)

The authenticated `/rooms/:id/mailbox` endpoint supports POST (opaque encrypted operation), GET (up to 25 opposite-peer updates), and DELETE (recipient acknowledgements). The client encrypts with the room's AES-GCM key before upload. The server never receives that key. Retention is 30 days, with 2,000 updates / 16 MiB per room. Mailboxes persist beside pairing state when STATE_FILE is configured. Photos continue over direct peer channels. Enable offline delivery on both devices in Project tools → People and connection status. Both peers require the updated app.

The 1.1.0 container is deployed locally as the-list-signal-1 and healthy at http://127.0.0.1:5174. The complete native Windows sync integration passed against it, including offline mailbox delivery. Existing pairing volumes were preserved. Use the same the-list Compose project name for upgrades.
