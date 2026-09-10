# Enterprise Windows UI Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify the enterprise Windows Flutter UI to the approved home, navigation, account, and security surfaces without changing other platforms.

**Architecture:** Extend the existing `EnterpriseUiPolicy` boundary and keep enterprise-only widgets in the desktop enterprise widget layer. Existing RustDesk widgets remain available for non-enterprise builds; enterprise mode hides navigation and actions rather than deleting shared capabilities.

**Tech Stack:** Flutter, Dart, GetX, Flutter widget tests

**Spec:** `docs/superpowers/specs/2026-09-10-enterprise-windows-ui.md`

## Global Constraints

- Enterprise changes apply only to customized Windows builds.
- macOS and non-enterprise Windows retain original UI behavior.
- Main window remains fixed at 1280 x 720.
- Existing mandatory Feishu login and managed unattended authentication must not regress.

---

### Task 1: Enterprise policy and top layout

**Files:**
- Modify: `flutter/lib/desktop/widgets/enterprise_feishu_login_gate.dart`
- Modify: `flutter/lib/desktop/widgets/enterprise_desktop_home.dart`
- Modify: `flutter/lib/desktop/pages/connection_page.dart`
- Test: `flutter/test/enterprise_feishu_login_gate_test.dart`
- Test: `flutter/test/enterprise_desktop_home_layout_test.dart`

**Interfaces:**
- Consumes: `EnterpriseUiPolicy.enabled`, `EnterpriseLocalIdCard`
- Produces: enterprise visibility getters and `EnterpriseAccountButton`

- [ ] Add failing policy tests for Favorites, settings tabs, and advanced security visibility.
- [ ] Add failing widget tests for title/ID alignment and the account button sharing the `Your Desktop` title row.
- [ ] Run the focused tests and confirm the new assertions fail.
- [ ] Add the minimal policy getters and enterprise home/account widgets.
- [ ] Wire the account button to `logOutConfirmDialog` using the Feishu display name only.
- [ ] Run the focused tests and confirm they pass.

### Task 2: Accessible Devices panel and user labels

**Files:**
- Modify: `flutter/lib/common/widgets/my_group.dart`
- Create: `flutter/test/enterprise_group_panel_test.dart`

**Interfaces:**
- Consumes: `shouldUseEnterpriseWindowsGate`
- Produces: `accessibleDevicesPanelWidth` and `enterpriseUserDisplayLabel`

- [ ] Add failing tests asserting 200 px enterprise width, 150 px original width, display-name output, and `Unknown user` fallback.
- [ ] Run the focused test and confirm failure.
- [ ] Use the enterprise width in landscape mode and remove email fallback/suffixes in enterprise display labels.
- [ ] Run the focused test and confirm it passes.

### Task 3: Favorites removal

**Files:**
- Modify: `flutter/lib/models/peer_tab_model.dart`
- Modify: `flutter/lib/common/widgets/peer_tab_page.dart`
- Modify: `flutter/lib/common/widgets/peer_card.dart`
- Test: `flutter/test/enterprise_feishu_login_gate_test.dart`

**Interfaces:**
- Consumes: `EnterpriseUiPolicy.showFavorites`
- Produces: enterprise mode with no Favorites tab or favorite mutations

- [ ] Add a failing policy assertion that enterprise mode hides Favorites and original mode retains it.
- [ ] Disable the Favorites tab for enterprise Windows.
- [ ] Hide the bulk Add to Favorites action for enterprise Windows.
- [ ] Suppress per-peer add/remove favorite actions for enterprise Windows.
- [ ] Run focused peer and policy tests.

### Task 4: Settings simplification

**Files:**
- Modify: `flutter/lib/desktop/pages/desktop_setting_page.dart`
- Test: `flutter/test/enterprise_feishu_login_gate_test.dart`

**Interfaces:**
- Consumes: enterprise settings visibility getters
- Produces: enterprise settings with General, Security, and Display tabs only; Security contains Permissions only

- [ ] Add failing assertions for Account, Printer, About, 2FA, Change ID, and lower Security visibility.
- [ ] Filter enterprise setting tabs to General, Security, and Display.
- [ ] Render only Permissions in enterprise Security while preserving original Security elsewhere.
- [ ] Run the focused tests and static analysis.

### Task 5: Verification

**Files:**
- Verify: all files above

**Interfaces:**
- Consumes: completed tasks 1-4
- Produces: tested enterprise Windows UI change set

- [ ] Run `dart format` on changed Dart files.
- [ ] Run all enterprise Flutter tests.
- [ ] Run `flutter analyze` on changed production and test files.
- [ ] Review `git diff --check`, `git diff`, and `git status --short`.
- [ ] Confirm no unrelated or `.superpowers/` files are staged.
