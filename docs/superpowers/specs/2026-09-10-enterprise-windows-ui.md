# Enterprise Windows UI Simplification Spec

## Scope

- Apply only when `shouldUseEnterpriseWindowsGate` is true.
- Preserve non-enterprise Windows and macOS UI behavior.
- Keep the existing enterprise login, identity, resident-process, fixed-window, update, and unattended-auth behavior unchanged.

## Home

- Keep the fixed 1280 x 720 enterprise home.
- Align the right-side `Your Desktop` title and local ID with the left remote-control title and remote-ID input.
- Place the account action at the far right of the same horizontal title row as `Your Desktop`.
- Keep local-ID copy behavior and do not show a local-ID overflow menu.
- Make the Accessible Devices left panel 200 px wide, matching the address-book side panel.
- Show Feishu display names in the Accessible Devices user list. Never show the email-style account identifier; use `Unknown user` when no display name is available.

## Removed enterprise surfaces

- Remove Favorites tab, favorite mutations, and favorite bulk action.
- Remove Account, Printer, and About tabs from Settings.
- Remove the 2FA, Change ID, and lower Security cards from the Security page while retaining the Permissions card.
- Keep the already-hidden Network tab hidden.

## Account action

- Clicking the home account button opens a compact menu that shows the Feishu display name and a logout action.
- Logout continues to use the existing confirmation and enterprise login gate.
