# Windows Feishu Enterprise Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a Windows-only RustDesk enterprise build gated by Feishu login, with API-assigned ID and hidden administrator auto-authentication.

**Architecture:** Extend the existing rustdesk-api OIDC completion with a transactional device-identity allocator. Add a Windows enterprise Cargo feature so hbb_common and Rust core remain inert until an atomic managed identity is applied; Flutter renders a Feishu-only gate. Reuse the existing personal address-book hash authentication path for administrator no-confirm connections.

**Tech Stack:** Go, Gin, GORM, Rust, Cargo, Flutter/Dart, SQLite-compatible migrations, RustDesk protobuf and IPC.

**Spec:** `docs/superpowers/specs/2026-09-08-windows-feishu-enterprise-client-design.md`

## Global Constraints

- Windows enterprise behavior requires both `target_os = "windows"` and Cargo feature `enterprise-windows`.
- macOS and ordinary Windows builds retain upstream behavior.
- hbbs is not modified; deliberate third-party bypass is out of scope.
- No credential, API master key, token, or server login secret may enter Git or logs.
- Production changes follow test-first red-green-refactor.
- Do not push any repository until explicit user approval.

---

### Task 1: Repair and feature-gate hbb_common identity behavior

**Files:**
- Modify: `D:/codex/hbb_common/Cargo.toml`
- Modify: `D:/codex/hbb_common/src/config.rs`
- Modify: `D:/codex/hbb_common/src/password_security.rs`
- Test: focused unit tests colocated in the modules above

**Interfaces:**
- Produces: `Config::apply_managed_identity(id: &str, password: &str) -> ResultType<()>`, `Config::clear_managed_identity() -> ResultType<()>`, and managed-active query.

- [ ] Add failing enterprise-feature tests proving `Config::load()` and `Config::get_id()` do not generate an ID, normal setters cannot mutate managed identity, temporary passwords are empty, and verification is permanent-password-only.
- [ ] Run `cargo test -p hbb_common --features enterprise-windows` and confirm failures are caused by missing enterprise behavior.
- [ ] Fix the existing `key`/`k` compile defect and add the `enterprise-windows` feature.
- [ ] Implement atomic validated apply/clear operations and block ordinary ID/password mutation in enterprise builds.
- [ ] Force password approval and permanent-only verification; disable temporary-password generation.
- [ ] Run feature and non-feature hbb_common tests and commit in `D:/codex/hbb_common`.

### Task 2: Add transactional API device identities

**Files:**
- Create: `D:/codex/rustdesk-api/model/deviceIdentity.go`
- Create: `D:/codex/rustdesk-api/service/deviceIdentity.go`
- Create: `D:/codex/rustdesk-api/service/deviceIdentity_test.go`
- Modify: `D:/codex/rustdesk-api/service/service.go`
- Modify: `D:/codex/rustdesk-api/cmd/apimain.go`
- Modify: `D:/codex/rustdesk-api/config/config.go`

**Interfaces:**
- Produces: `AllocateOrGetDeviceIdentity(tx *gorm.DB, userID uint, machineUUID string, info DeviceInfo) (*DeviceIdentity, string, error)`.

- [ ] Write failing tests for first allocation, same-pair idempotency, one user/two machines, two users/one machine, archived rejection, 100 concurrent same-pair calls, globally unique IDs, and credential encrypt/decrypt failure.
- [ ] Run the focused Go tests and confirm expected failures.
- [ ] Add the model, unique indexes, migration version, AEAD master-key loader, ID generator, conflict retry, and transactional allocator.
- [ ] Run focused tests and `go test ./...`; if Go is unavailable, record the blocker and use the configured bundled runtime or CI without claiming a pass.
- [ ] Commit the API identity layer.

### Task 3: Extend OIDC completion atomically

**Files:**
- Modify: `D:/codex/rustdesk-api/http/request/api/oauth.go`
- Modify: `D:/codex/rustdesk-api/http/response/api/user.go`
- Modify: `D:/codex/rustdesk-api/http/controller/api/ouath.go`
- Modify: `D:/codex/rustdesk-api/http/controller/api/login.go`
- Test: new controller tests beside API controller tests

**Interfaces:**
- Consumes: API allocator from Task 2.
- Produces: optional login response `device { rustdesk_id, permanent_password, password_version, status }`.

- [ ] Write failing controller tests for Windows enterprise success, empty UUID rejection, disabled/archived rejection, no device allocation for macOS/web, Feishu-only login options, and no half-success token when allocation fails.
- [ ] Run tests and confirm expected failures.
- [ ] Validate enterprise client metadata, restrict enterprise login options to configured Feishu OIDC op, and complete token plus identity in one transaction.
- [ ] Add the optional response payload and verify response/log middleware never logs its body.
- [ ] Run focused and full Go tests and commit.

### Task 4: Provide admin-only address-book auto-auth material

**Files:**
- Modify: relevant `D:/codex/rustdesk-api/http/controller/api/ab.go` or add a focused company-peer controller
- Modify: relevant response types under `D:/codex/rustdesk-api/http/response/api/`
- Test: permission and payload tests

**Interfaces:**
- Produces: administrator-only peer authentication hash compatible with `try_get_password_from_personal_ab`; ordinary users receive no hash.

- [ ] Write failing tests proving administrators receive one peer's compatible auth material and ordinary users never receive it.
- [ ] Confirm the expected RustDesk hash wire format from client code before implementing serialization.
- [ ] Implement least-privilege filtering without exposing plaintext credentials.
- [ ] Run API tests and commit.

### Task 5: Wire enterprise feature and atomic service IPC

**Files:**
- Modify: `D:/codex/rustdesk-client/Cargo.toml`
- Update gitlink: `D:/codex/rustdesk-client/libs/hbb_common`
- Modify: `D:/codex/rustdesk-client/src/ipc.rs`
- Modify: `D:/codex/rustdesk-client/src/flutter_ffi.rs`
- Modify: `D:/codex/rustdesk-client/src/core_main.rs`
- Test: Rust unit tests for IPC and mutation bypasses

**Interfaces:**
- Consumes: hbb_common managed identity API from Task 1.
- Produces: service IPC commands to apply/deactivate a managed identity atomically.

- [ ] Initialize the submodule at the tested Task 1 commit and add the feature dependency wiring.
- [ ] Write failing tests for valid apply, invalid payload rollback, deactivate, and rejection of ordinary CLI/IPC ID/password setters.
- [ ] Implement IPC/FFI commands with explicit success/error responses.
- [ ] Run Rust tests with and without the feature and commit the client gitlink plus IPC changes.

### Task 6: Enforce the Rust-core authentication gate

**Files:**
- Modify: `D:/codex/rustdesk-client/src/server.rs`
- Modify: `D:/codex/rustdesk-client/src/rendezvous_mediator.rs`
- Modify: `D:/codex/rustdesk-client/src/lan.rs`
- Modify: `D:/codex/rustdesk-client/src/ui_interface.rs`
- Test: focused Rust gate tests

**Interfaces:**
- Consumes: managed-active state from Tasks 1 and 5.
- Produces: no rendezvous, direct server, API sync, or LAN discovery until managed identity is active.

- [ ] Write failing truth-table tests for inactive, missing-ID, authenticated, logout, and network-timeout states.
- [ ] Implement the service gate before `RendezvousMediator::start_all` and explicit blocks for discovery and alternate entry points.
- [ ] Ensure activation starts and deactivation stops all reachable services without a busy loop.
- [ ] Run Rust tests and commit.

### Task 7: Parse and apply the enterprise OIDC response

**Files:**
- Modify: `D:/codex/rustdesk-client/src/hbbs_http/account.rs`
- Modify: `D:/codex/rustdesk-client/flutter/lib/common/hbbs/hbbs.dart`
- Modify: generated/handwritten bridge boundary only as required by existing project convention
- Test: Rust response tests and Dart model tests

**Interfaces:**
- Consumes: API `device` response from Task 3 and IPC from Task 5.
- Produces: authenticated state only after managed identity apply succeeds.

- [ ] Write failing tests for valid response, missing device, invalid ID/password, service apply failure, and macOS response compatibility.
- [ ] Extend response types and call the atomic apply operation before persisting authenticated UI state.
- [ ] Roll back token/user info on apply failure.
- [ ] Run Rust and Dart tests and commit.

### Task 8: Build the non-dismissible Feishu-only Flutter gate

**Files:**
- Modify: `D:/codex/rustdesk-client/flutter/lib/models/user_model.dart`
- Modify: `D:/codex/rustdesk-client/flutter/lib/desktop/pages/desktop_tab_page.dart`
- Create: `D:/codex/rustdesk-client/flutter/lib/desktop/widgets/enterprise_feishu_login_gate.dart`
- Modify: `D:/codex/rustdesk-client/flutter/lib/common/widgets/login.dart`
- Test: Flutter widget/model tests

**Interfaces:**
- Produces: `checking`, `unauthenticated`, `authenticated`, and `offlineGrace` UI states.

- [ ] Write failing widget tests showing that unauthenticated enterprise Windows exposes only the Feishu action and cannot dismiss into the app.
- [ ] Write failing tests that authenticated state restores the original desktop tabs and non-enterprise/macOS remains unchanged.
- [ ] Implement the top-level gate, configured Feishu op selection, 401 logout, timeout grace, jitter, and exponential backoff.
- [ ] Run Flutter tests and commit.

### Task 9: Lock password/network UI and disable LAN discovery

**Files:**
- Modify: `D:/codex/rustdesk-client/flutter/lib/desktop/pages/desktop_home_page.dart`
- Modify: `D:/codex/rustdesk-client/flutter/lib/desktop/pages/desktop_setting_page.dart`
- Modify: `D:/codex/rustdesk-client/flutter/lib/models/peer_tab_model.dart`
- Modify: core option setters found in Tasks 1, 5, and 6
- Test: Flutter widget tests and Rust option/discovery tests

- [ ] Write failing tests that enterprise Windows has no password board, password settings, network tab, unlock action, or discovery tab, and cannot bypass restrictions through core setters.
- [ ] Implement UI removal plus core hard settings for company ID/API/key/relay values.
- [ ] Disable LAN listener startup and active discovery entry points.
- [ ] Run feature and non-feature tests and commit.

### Task 10: Integrate administrator automatic authentication

**Files:**
- Modify: `D:/codex/rustdesk-client/src/client.rs`
- Modify: `D:/codex/rustdesk-client/flutter/lib/models/ab_model.dart`
- Test: focused Rust and Dart address-book authentication tests

- [ ] Write failing tests proving admin company entries select the API-provided compatible hash, no password prompt appears, and ordinary entries have no credential.
- [ ] Reuse the existing personal-address-book password source with the company admin payload; never persist plaintext in Flutter address-book data.
- [ ] Verify the target accepts through permanent-password mode without local confirmation.
- [ ] Run tests and commit.

### Task 11: End-to-end verification and review

**Files:**
- Create: `D:/codex/rustdesk-client/docs/enterprise-windows-build.md`
- Update: CI/build workflow only if required for the new feature

- [ ] Run clean API tests, hbb_common feature/non-feature tests, Rust client feature/non-feature tests, Flutter tests, formatting, and lints.
- [ ] Build a Windows enterprise artifact and a normal artifact; verify macOS/non-feature compilation through available CI or target check.
- [ ] Exercise fresh install, login allocation, restart persistence, admin auto-connect, logout/401 shutdown, network failure grace, locked settings, and LAN silence.
- [ ] Perform task-level and whole-branch code review; resolve Important/Critical findings.
- [ ] Present commits, test evidence, known limitations, build instructions, and rollback steps. Do not push until the user authorizes it.

