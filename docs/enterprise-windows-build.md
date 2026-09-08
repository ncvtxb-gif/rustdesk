# Enterprise Windows Build

This build is an explicit Windows-only variant. Ordinary Windows builds and all macOS builds omit the `enterprise-windows` Cargo feature and retain upstream behavior.

## Source revisions

The first reproducible baseline for this build is:

- `rustdesk-client`: `e105889a93d0eae13bbfd006de945c54dbcc6d28`
- `hbb_common`: `965f5ca8462a6282ddcd50abbb241927f9483c22`
- `rustdesk-api`: `7c51b2c6e2f38c4b101412009d311d75cc588337`

After pulling the client repository, initialize and verify its pinned submodule before building:

```powershell
git submodule sync --recursive
git submodule update --init --recursive
git rev-parse HEAD
git -C libs/hbb_common rev-parse HEAD
git -C D:\codex\rustdesk-api rev-parse HEAD
```

The three results must match the approved release record. If an `hbb_common` change is promoted, first commit it in that repository, then update and commit the `libs/hbb_common` gitlink in `rustdesk-client`. Never build from an uncommitted submodule working tree.

## Required GitHub repository secrets

Configure these under **Settings > Secrets and variables > Actions**. Do not put their values in source, workflow inputs, logs, artifacts, issue text, or release notes.

- `RS_PUB_KEY`: public key paired with the company hbbs deployment.
- `RENDEZVOUS_SERVER`: company ID/rendezvous server address.
- `API_SERVER`: absolute HTTPS base URL of the locked company API.

The workflow and local build entry refuse an enterprise build when any value is empty or when `API_SERVER` is not an absolute HTTPS URL. In an enterprise Windows build, the API URL is compiled into the locked override settings, the rendezvous address is compiled as the production server, and the public key is compiled as the server key. Ordinary and macOS builds do not enable this behavior. Rotate secrets through repository settings and rebuild; do not edit workflow YAML to embed them.

## GitHub Actions build

1. Open **Actions > Build the flutter version of the RustDesk**.
2. Choose **Run workflow**.
3. Set `enterprise-windows` to `true`.
4. Keep artifact upload enabled for a release candidate and run the workflow from the approved commit.
5. Confirm the Windows build log contains `enterprise-windows` in the printed Cargo feature list. Do not print secret values while diagnosing a build.

Leaving `enterprise-windows` at `false`, or invoking the existing reusable workflow without that input, produces the ordinary build. The flag is added only to the Windows command; macOS, Linux, Android, iOS, and web commands are unchanged.

## Local Windows build

Set the three build environment variables only in the current protected shell or CI secret store, then run:

```powershell
python .\build.py --portable --hwcodec --flutter --vram --skip-portable-pack --enterprise-windows
```

`build.py` rejects `--enterprise-windows` on non-Windows hosts. Do not use the flag for the macOS package.

## Verification

Run the checks appropriate to the release environment:

```powershell
python -m py_compile .\build.py
cargo test --features enterprise-windows
flutter test .\flutter\test\enterprise_login_response_test.dart
git diff --check
```

In the API repository:

```powershell
go test ./...
```

Before deployment, verify on a clean Windows VM that the client has no ID and opens no rendezvous, direct, HTTP-sync, or LAN-discovery service before Feishu login; bootstrap succeeds after login; logout and session expiry terminate active service and sessions; network settings and password controls remain unavailable. Also run an ordinary Windows build and an upstream macOS build as regression checks.

## Rollback

1. Stop distribution of the affected enterprise artifact and retain its workflow run ID and checksums for audit.
2. Select the last approved trio of client, submodule, and API commits from the release record.
3. Revert forward with `git revert`; do not rewrite shared history or use `git reset --hard` on release branches.
4. Rebuild with `enterprise-windows: true` and the current repository secrets.
5. Run the verification above before replacing the artifact. If only the enterprise client is rolled back, confirm its bootstrap and address-book contracts remain compatible with the deployed API.

To return to an ordinary upstream client, build with `enterprise-windows: false`. This removes the enterprise feature but does not roll back server-side identities or API data.
