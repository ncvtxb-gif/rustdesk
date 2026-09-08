# Windows Feishu Enterprise Client Design

## Goal

Build a Windows-only enterprise RustDesk client that cannot operate before Feishu OIDC authentication. After successful authentication, the API assigns a stable RustDesk ID and hidden per-device credential; authorized administrators connect from the company address book without target-user approval. macOS retains upstream behavior.

## Scope

- Windows enterprise builds only, guarded by an explicit `enterprise-windows` feature.
- The login surface exposes only the configured Feishu OIDC provider.
- Before authentication the client has no RustDesk ID and starts no hbbs registration, direct server, HTTP sync, or LAN discovery.
- The API owns ID and credential allocation.
- Network settings are hidden and immutable; LAN discovery is disabled in UI and core code.
- One-time and visible permanent-password controls are removed. A hidden credential remains as the existing RustDesk authentication primitive.
- Administrators receive automatic address-book authentication material; ordinary users do not.
- No password view/reset UI is built in this phase.
- hbbs is not modified and deliberate third-party-client bypass is out of scope.

## Identity Rules

The identity key is `(feishu_user_id, machine_uuid)`. A repeated login by the same user on the same machine returns the same RustDesk ID and credential. The same user on another machine receives a different identity. A different user may freely log in on the same machine and receives or resumes that user's separate identity. Only the currently authenticated identity is active locally.

RustDesk IDs and allocation UUIDs are globally unique and never reused after archival. An archived identity cannot reactivate. `machine_uuid` alone is not unique because account switching is allowed.

## API Model and Transaction

Add `DeviceIdentity` with allocation UUID, user ID, machine UUID, RustDesk ID, encrypted credential, credential version, status, last-auth timestamp, and timestamps. Enforce unique indexes on allocation UUID, RustDesk ID, and `(user_id, machine_uuid)`.

OIDC completion creates the access token and identifies the authenticated user. First device bootstrap generates the ID and a cryptographically random credential, encrypts the credential with an API master key using authenticated encryption, and commits the identity. Conflicts retry through database uniqueness, not a preflight-only check. Empty machine UUID, non-Windows enterprise clients, disabled users, and archived identities fail closed.

The successful OIDC login response returns the access token only; it never returns `permanent_password`. The Windows service exchanges that bearer token at `POST /api/managed-device/bootstrap` with `{machine_uuid, platform: "windows"}`. A successful bootstrap returns `rustdesk_id`, the hidden `permanent_password`, `password_version`, status, echoed `machine_uuid`, and `session_expires_at`. The service validates the response, applies the identity atomically, uploads the compatible authentication hash, and never logs or persists the token or plaintext credential outside the managed identity store.

## Client State Machine

Windows enterprise state is `checking`, `unauthenticated`, `authenticated`, or `offline_grace`. The Rust service and Flutter UI share an on-disk/IPC managed-identity marker; the service never stores the Feishu token.

On fresh start, the Rust core blocks rendezvous registration, direct-server startup, API sync, and LAN listeners. Flutter displays a non-dismissible Feishu-only gate. After OIDC success, one Rust-side atomic operation validates and stores the API ID and credential, forces permanent-password verification and password approval mode, marks the managed identity active, and starts rendezvous services. Partial failure rolls back and remains gated.

On explicit logout or confirmed HTTP 401, the service deactivates first, stops registration and inbound service, then clears token and local managed identity. Network timeouts do not clear a valid identity; checks use jitter and exponential backoff.

## Administrator Auto-authentication

Reuse RustDesk's existing address-book password-hash path. The API returns automatic authentication material only for callers with administrator unattended-control permission. The administrator chooses a company address-book device and connects without seeing or entering the credential. The target validates the hidden permanent credential and accepts without local confirmation. Ordinary address books never receive the material.

## UI and Policy

Unauthenticated Windows enterprise builds show only company branding, explanatory text, and `使用飞书登录`. There is no close path into the client. Authenticated builds restore remote desktop, file transfer, camera, terminal, address book, recent items, favorites, and search.

Password panels, password settings, other OIDC providers, username/password login, WebAuth, network settings, LAN discovery controls, and the discovery tab are absent. Core setters, IPC, CLI, import paths, and discovery entry points also reject these operations.

## Platform Isolation

Use Cargo feature `enterprise-windows` combined with `target_os = "windows"`. Ordinary Windows builds and every macOS build keep upstream semantics. Do not use broad custom-client detection as the gate.

## Security

- API master key is supplied outside Git and validated at startup.
- Credentials are encrypted at rest with AEAD and excluded from logs.
- Administrator authorization is enforced by the API, not by hidden UI.
- Identity application is atomic across ID, credential, verification mode, and active marker.
- No unauthenticated client core starts a reachable inbound service.

## Verification

Tests cover API idempotency and concurrency, account/device combinations, archival, encryption, response filtering, and admin-only address-book material. Rust tests cover both ID-generation entry points, atomic identity apply/clear, setter bypasses, permanent-only verification, and service/LAN gates. Flutter tests cover the non-dismissible Feishu-only gate and authenticated restoration. Integration verifies fresh install, OIDC allocation, hbbs registration only after login, admin automatic connection, logout/401 shutdown, network failure grace, settings locks, LAN silence, restart persistence, and macOS/non-enterprise regression.
