# Tildeck Project Foundation

Status: Foundation implemented; product implementation in progress (see [Product implementation plan](#product-implementation-plan))

This document separates the repository's current state from the approved foundation that a later implementation task must build. A planned item does not exist until its status and verification evidence say otherwise. Nothing described as planned in this document is implemented.

## Current truth

Updated on 2026-09-28.

- Git repository on branch `main`, pushed to the private GitHub repository `Tildeck/tildeck` (created 2026-09-30 with Shlomi's authorization; to be made public when ready). Commits use the GitHub noreply address, set in this repository's local Git config, because the account blocks pushes that expose a private email. The repository baseline, the server shell, the admin panel shell, both Compose files, `.env.example`, and `scripts/local.sh` exist (see the implementation plan statuses). The client shell in `app/` and `scripts/verify.sh` exist. All workflow scripts, the CI workflows, and the Dependabot configuration exist and run on GitHub.
- The server and panel toolchains run in containers pinned by digest in `server/Dockerfile`: `python:3.14-slim`, `uv` 0.12.9, and `node:26-alpine`. PostgreSQL is `postgres:18`, pinned by digest in both Compose files. The Flutter toolchain (`ghcr.io/cirruslabs/flutter:3.44.0`: Flutter 3.44.0, Dart 3.12, Android SDK 36, Java 21), the OpenAPI generator, shellcheck, shfmt, and the test database are pinned by digest in `scripts/toolchain/Dockerfile`.
- Docker from WSL must run in a login shell (`bash -l`); outside it, the Docker Desktop credential helper is not on `PATH` and image pulls fail.
- The GitHub organization `Tildeck` exists (created by Shlomi); its settings match his other organizations (checked 2026-09-29).
- Repository settings (2026-09-30): private; squash merge only with the pull request title and body; branches deleted after merge; issues on, wiki and projects off; description and homepage `https://tildeck.com`; Dependabot alerts and security updates on; Actions token read-only by default (organization setting); focused labels (`area:*`, `priority:*`, `nature:*`); an empty `release` environment for the Android signing secrets. Not available while the repository is private on the free plan, and to be enabled when it becomes public: branch protection or rulesets requiring the `summary` check, secret scanning and push protection, and private vulnerability reporting. The GitHub CLI on the host is authenticated as `ShlomiPorush` with `repo` and `workflow` scopes.
- The domain `tildeck.com` is registered by Shlomi at Cloudflare. No DNS records or services are configured for the project.
- Host: Windows 10 Pro with WSL 2 distribution `Ubuntu-26.04` and Docker Desktop.
- Tools on the Windows host: `git`, `docker`, `gh`, Visual Studio Build Tools 2022 (17.14) with the C++ desktop tools, and Flutter 3.44.0 (the pinned version, revision 559ffa3f75, installed on 2026-09-30 with Shlomi's approval at `C:\src\flutter`, on the user PATH; first installed under the user profile, then moved, because Flutter's native build hooks fail when the SDK path contains a space). Not installed: `node`.
- Tools inside `Ubuntu-26.04`: `git`, `docker`. Not installed: `flutter`, `dart`, `node`, `java`, `shellcheck`, `shfmt`.
- Verified on 2026-09-28 inside WSL with only Docker: the server test image builds, `ruff check` and `ruff format --check` pass, and 19 pytest tests pass against a throwaway PostgreSQL 18 container. The panel passes `eslint` and `nuxt typecheck` in the `panel-check` stage. The runtime image builds with the panel.
- Verified on 2026-09-28 with `scripts/local.sh`: it fails with a clear message when `docker-compose-dev.yml` is missing; `up -b -d` builds the image and brings both services to healthy; the server's PID 1 runs as UID 999 and runs the freshly built image; a row written before `down` is still there after `up`. The panel shell was screenshotted with Playwright (Chromium) in English LTR and Hebrew RTL, light and dark, at 1280x800 and 390x844, including the mobile menu and the language and theme toggles, with the Heebo font loaded and no console errors.
- Verified on 2026-09-30 inside WSL with only Docker: in the Flutter toolchain container, `dart format` is clean, `flutter analyze` finds no issues, and 10 tests pass (6 server-check tests and 4 golden images). `scripts/local.sh apk` builds a debug APK whose badging reads package `com.tildeck.app`, label `Tildeck`, target SDK 36, with the INTERNET permission. `scripts/local.sh contract` re-exports `server/openapi.json` unchanged and regenerates the Dart client. `scripts/windows.ps1` stopped with a clear message naming the missing Flutter before it was installed (PowerShell 7 and Windows PowerShell 5.1); after the install, `check` passes, `build` produces `out\windows\tildeck.exe` with the working tree unchanged, and the executable starts a responsive window titled Tildeck. The window content could not be captured from the automation session (the Flutter surface is GPU-rendered), so the rendered Windows screen has not been inspected; the same widgets are covered by the golden images. The Windows and Android launcher icons are still Flutter's defaults until the logo is decided.
- Verified on 2026-09-30: `scripts/verify.sh` passes a full run in WSL with only Docker in 162 seconds (server: ruff and 19 pytest tests against a throwaway PostgreSQL; panel: lint, type checks, static build; image: runtime image with the panel, UID 999, health check on `/api/health/ready`; app: format, analyze, 10 tests, debug APK; contract: no drift; guards) and leaves no containers, networks, or temporary files. Each of these faults, introduced on purpose and then reverted, fails its area with a clear message: Hebrew in a code file, a Unicode dash in documentation, a missing Hebrew locale key, `build:` in a Compose file, CRLF in a script, a stale `server/openapi.json`, and a hand-edited generated client. `--changed` selects only `guards` for a documentation change, `panel image guards` for a panel change, and every area for a change to shared tooling.
- Verified on 2026-09-30: `scripts/try-pr.sh --ref` on a throwaway branch with a server change carrying a new migration, a panel change, and an app change snapshotted the database, rebuilt and restarted only the server (verified image, UID 999), migrated to the new revision, served the changed panel, and built an APK; `restore` returned the database to its previous migration and rows (a row written during the preview was gone, the earlier row kept), rebuilt the server from the working tree, and removed the worktree, with the checkout untouched. Fetching a real pull request (`refs/pull/N/head`) is untested until the GitHub repository exists.
- Verified on 2026-09-30: `scripts/release.sh` changes nothing in a dry run and lists every preflight problem; a real run refuses without `--bump` or with preflight problems. A real `--bump minor` run in a temporary clone against a local bare repository as origin ran the full verify, committed only `VERSION` (0.1.0), `app/pubspec.yaml` (0.1.0+1000), and `CHANGELOG.md`, created the annotated tag `v0.1.0`, and pushed without force; a second run refused with nothing under Unreleased.
- Verified on 2026-09-30: actionlint passes on all workflows (it is part of the guards), `.github/dependabot.yml` validates against the SchemaStore schema, a release APK built with a throwaway keystore through the same variables as the publish workflow is signed with that key (and with the debug key when none is given), the changelog section extraction returns exactly one version's section, and a stale `pubspec.lock`, `uv.lock`, or `package-lock.json` fails its build. The workflows themselves have not run on GitHub.
- Verified on 2026-09-28: the production `docker-compose.yml` ran end to end from a temporary directory with a bind-mounted data directory, the development image tagged as a release, and a generated key. Both services became healthy, both PID 1 processes ran as UID 999 with a read-only server root filesystem, `APP_ENV` was forced to `production`, and with a placeholder key the server refused to start. Everything was removed afterwards.

## Product intent and boundaries

**Problem.** Cross-device SSH clients that sync hosts, keys, and settings between desktop and mobile charge a subscription for sync. Tildeck is a free, open source SSH client with end-to-end encrypted sync through a server that users run themselves.

**Intended users.**

- End users: developers and operators who manage servers from a Windows computer and an Android phone.
- Operators: whoever runs a Tildeck sync server, for themselves, a family, or a team. They manage it through a web admin panel.

**Stage.** Pre-implementation. No product code exists.

**First release scope (product, after the foundation):**

- Client: host management with groups, SSH sessions in tabs, password and key authentication, host key verification, basic SFTP, a local encrypted vault, and end-to-end encrypted sync.
- Accounts: registration, email verification, new-device approval, security notifications, and a recovery key. There is no password reset, by design.
- Server: authentication, device management, and storage of opaque encrypted records.
- Admin panel: first-run setup, users and devices, all server settings, and an activity log.

**Later:** port forwarding, snippets, and other client features, each approved separately.

**Non-goals for the first release:**

- macOS, iOS, and Linux desktop clients.
- A hosted public sync service, paid tiers, or billing.
- Server-side or admin access to plaintext user data. Neither the server nor an administrator can read vault contents.
- Telemetry or analytics.
- Password reset. A lost master password without the recovery key means the synced data is lost. Shlomi accepted this.

**Deployment shape.** Users install the client from GitHub Releases (Android APK, Windows package). Operators run the sync server with Docker Compose: one server container that also serves the admin panel, and one PostgreSQL container. Email is sent through an SMTP provider chosen by the operator.

**Constraints that shape the architecture:**

- Zero cost to use. No paid certificates, stores, or services are required to install or run the product.
- Secrets never leave a device unencrypted. Encryption, decryption, and key derivation happen only in the client.
- Android blocks cleartext HTTP by default, so a real sync deployment needs HTTPS in front of the server.

## Preparation decisions

| Decision | Status | Choice | Rationale or blocker |
|---|---|---|---|
| Project name | Approved | Tildeck | Chosen by Shlomi after availability checks on GitHub, pub.dev, Google Play, domains, and web search. |
| Domain and identifiers | Approved | `tildeck.com`; Android application ID `com.tildeck.app` | Shlomi owns `tildeck.com`. The application ID cannot change after the first public release. |
| Publication posture | Approved | Public-ready open source | Shlomi chose a public open source project. |
| License | Approved | Apache-2.0 for all code | Simple, widely adopted, includes a patent grant. |
| Repository language | Approved | English, with Hebrew only in the listed locale files | Follows from the public-ready posture. |
| Client platforms | Approved | Windows and Android | Shlomi limited the first release to the platforms he uses. |
| Client technology | Approved | Flutter (Dart) | One codebase for Windows and Android, native terminal rendering, good touch and keyboard handling on Android. |
| SSH and terminal libraries | Provisional | `dartssh2` for SSH and SFTP, `xterm` (xterm.dart) for the terminal | Checked 2026-09-30: `dartssh2` 4.1.0 (MIT) is maintained by vicajilau, released 2026-09-04, one open issue. `xterm` 4.0.0 (MIT) was last released 2024-02 and last committed 2025-06 with 108 open issues: a maintenance risk, judged in practice in product step 2. |
| Sync model | Approved | Own sync server with end-to-end encryption | Shlomi chose this over syncing through third-party storage. |
| Server technology | Approved | Python with FastAPI, SQLAlchemy (async), asyncpg, and Alembic, managed with `uv` | The same stack as Pay's backend, which Shlomi knows. Proven Pay code (settings registry, settings encryption, activity log, email, migrations) can be reused. |
| Client and server contract | Approved | The server's OpenAPI document is the contract. The Dart client code for the API is generated from it, and CI fails when the committed OpenAPI document or the generated client is out of date. | Client and server are in different languages; generation plus a CI check keeps them from drifting apart. |
| Database | Approved | PostgreSQL | Shlomi chose PostgreSQL over SQLite. Cost accepted: a second container, `pg_dump` backups, and major-version upgrade procedures. |
| Admin panel | Approved | Web admin panel in the first release, with the look and feel of Shlomi's Pay admin panel | Shlomi's requirement. Management and oversight belong in an admin interface. |
| Admin panel technology | Approved | Nuxt (Vue) with Tailwind, `@nuxtjs/i18n`, and `@nuxtjs/color-mode`, built as a static single-page app and served by the server | This is the stack of the Pay panel, which is the design reference. Flutter Web cannot reproduce that look without rebuilding it. A static build keeps one server container. |
| Reuse of Pay code | Approved | Code from Pay (`MosesGroups/payments`) may be reused in Tildeck under Apache-2.0 | Shlomi confirmed the right to release it under this license. |
| Settings model | Approved | Every operator setting is editable in the admin panel. A set environment variable wins and locks the field in the panel. | Shlomi's requirement, the same ruling as in Pay. See [Settings model](#settings-model). |
| Email | Approved | SMTP to an operator-chosen provider, configured as ordinary settings | Shlomi handles provider selection. See [Accounts, authentication, and email](#accounts-authentication-and-email). |
| Recovery | Approved | Recovery key issued at registration; no password reset | Shlomi accepted this. |
| Docker | Approved | Docker Compose for the server and PostgreSQL, in production and development | The server ships as a container image and depends on PostgreSQL. |
| Container registry | Provisional | GitHub Container Registry (GHCR) | Free for public images and integrated with GitHub Actions. |
| Build toolchains | Approved | Pinned toolchain containers for Flutter with the Android SDK, for Node, and for Python with `uv`, invoked by the workflow scripts | Shlomi chose containers. WSL needs only Docker, and local, CI, and release builds are identical. |
| Windows client builds | Approved | CI builds on a Windows runner; a PowerShell script for local Windows builds and runs | Flutter cannot build Windows desktop apps from WSL. Shlomi explicitly requested the PowerShell script. |
| Workflow scripts | Approved | WSL Bash `.sh` files under `scripts/`, plus the requested Windows script | Repository baseline, with the documented Windows exception. |
| Root layout | Approved | Minimal root with every file justified | Repository baseline. See [Planned repository root](#planned-repository-root). |
| Cryptography design | Approved (2026-09-30) in [docs/security-model.md](security-model.md) | Argon2id from the master password; separate derived key-encryption key and authentication key; a random vault key wrapped by the password and by the recovery key; per-record XChaCha20-Poly1305 via libsodium | Established primitives with an audited library. Vault and sync code merge only after the document is approved. |
| Admin panel sign-in | Approved (2026-09-30) | Separate administrator accounts with a password and mandatory TOTP, the first one created in first-run setup with a one-time setup token from the server log | The panel manages the server, not vaults, so it does not need vault keys. Pay's Entra sign-in does not fit a public self-hosted product. |
| Release artifacts | Provisional | Android APK, Windows package, server image in GHCR, all from one tagged release | Windows package format (zip, MSIX, or installer) is deferred. |
| Versioning | Provisional | One SemVer version for the whole product; single source of truth is a root `VERSION` file, as in Pay; the release workflow writes it into `app/pubspec.yaml`, and the server image and panel receive it at build time | Client, server, and panel ship together and share a contract. Three ecosystems need one neutral source. |
| Development database storage | Approved | Named volume in development, bind mount in production | PostgreSQL's `initdb` cannot set the permissions it needs on a bind mount of a Windows drive, and the repository lives on `C:`. Pay and hub use the same exception. |
| TLS termination | Approved | The operator's own TLS reverse proxy; Tildeck does not bundle one. Development and phone testing go through Shlomi's existing HTTPS proxy | Shlomi has a proxy ready (2026-09-30). |
| Client cryptography library | Approved | `sodium` 4.0.4, which builds libsodium 1.0.21 from source through a native build hook (verified on Linux, Windows with MSVC, and Android with the NDK) | The last release that supports Dart 3.12 in the pinned Flutter 3.44; 4.1 needs Dart 3.13. `sodium_libs` is discontinued, and `flutter_sodium` is unmaintained. |
| Product scope of the working version | Approved (2026-09-30) | The full first-release scope, built in the order of the product implementation plan | Shlomi: the proof of concept is a product that works. |
| Brand colors and mark | Provisional | Deep teal ink desk band with a bright teal accent; the mark is a tilde stroke on a rounded tile (`panel/public/favicon.svg`, `panel/app/components/AppLogo.vue`) | Proposed during the panel shell; awaiting Shlomi's review of the screenshots. No purple. |

## Publication and language policy

Tildeck is public-ready. Repository documentation, `AGENTS.md`, code, comments, identifiers, fixtures, tests, commit messages, Issues, pull requests, and review discussion are in English.

Hebrew text is allowed only in these locale files, whose exact paths are finalized when they are created:

- `app/lib/l10n/app_he.arb` (client)
- `panel/i18n/locales/he.json` (admin panel)
- `server/app/locales/he.json` (server emails and email link pages)

A CI guard scans all tracked text files for Hebrew characters and excludes only those exact paths. Tests that need Hebrew samples load them from the locale files.

## Planned architecture

| Component | Responsibility | Expected path | Status | Dependencies or blockers |
|---|---|---|---|---|
| Client app | Flutter app for Windows and Android: UI, SSH, terminal, SFTP, local vault, sync client, key derivation, encryption | `app/` | Shell exists | Security model before vault and sync |
| Sync server | FastAPI service: HTTP API for accounts, devices, and encrypted records; settings registry; email; serves the admin panel; CLI commands for operators | `server/` | Shell exists | None |
| API contract | Committed OpenAPI document exported from the server, including the protocol version and stable error codes | `server/openapi.json` | Exists | Sync server |
| Generated API client | Dart API client generated from the OpenAPI document and used by the app | `app/packages/tildeck_api/` (generated path package) | Exists | Regenerate with `scripts/local.sh contract` |
| Admin panel | Web UI for operators: first-run setup, users, devices, settings, activity log | `panel/` | Shell exists | Admin sign-in approval before the screens |
| Database | PostgreSQL storing accounts, devices, encrypted records, settings, and the activity log | Container from the official image | Exists (Compose) | Docker |
| Database migrations | Versioned, forward-only Alembic migrations applied by the server | `server/app/migrations/` | Exists (initial migration) | Sync server |
| Workflow scripts | Local, verify, try-PR, release, and the Windows client script | `scripts/` | Exist | Toolchain containers |
| CI | Path-filtered GitHub Actions | `.github/workflows/` | Written; not run until the repository exists | GitHub repository |
| Documentation | Foundation plan, security model, self-hosting guide | `docs/` | Foundation plan exists; others planned | None |

**Load-bearing boundaries:**

- Plaintext user secrets exist only in the client. The server API accepts and returns ciphertext and metadata only (record ID, revision, deletion marker, timestamps).
- Conflicts resolve per record: the highest revision wins, and deletions are kept as tombstones so they propagate to every device.
- The sync protocol is versioned. The server rejects an unsupported client with a stable error code, and the client shows a localized message.
- The admin panel talks only to the server's admin API. It never sees vault contents, and an administrator cannot read or decrypt user data.
- Terminal content is always rendered left-to-right, even when the surrounding UI is right-to-left.

## Settings model

Adopted from Pay's settings ruling:

- Every operator setting is declared once in a server-side registry with its key, environment variable, type, default, whether it is secret, and a description.
- Every registered setting is editable in the admin panel.
- A set environment variable wins over the stored value and locks the field. The panel shows that the value comes from the environment and does not allow editing it. The admin API reports the lock and refuses writes to a locked setting.
- Stored values are encrypted at rest.
- Sensitive values (passwords, keys, tokens, connection strings with credentials) are never returned by any API and never displayed in the panel, not even read-only and not when they come from the environment. The panel shows only their state: not configured, configured, or set by the environment.
- Every change is recorded in the activity log with the administrator, the time, and the setting key, never the value of a sensitive setting.

**Bootstrap exception.** A small set of values must exist before the server can reach its database or decrypt stored settings: the database connection and the settings encryption key. These are environment-only by necessity. The panel shows only that they are set, never their values. The list is kept minimal and documented in `.env.example`.

**Settings so far:** SMTP host, port, security mode (STARTTLS, TLS, or none for a local relay), username, password, and sender address; public server URL; registration mode (closed, invite, or open); days a device may stay idle before signing in again; and sign-in rate limits per account and per client address. The final list is set in the sync and panel phases.

## Accounts, authentication, and email

- The client derives two keys from the master password with Argon2id: an encryption key that never leaves the device, and an authentication key that is sent to the server. The server stores only a salted hash of the authentication key.
- Sign-in issues a token per device. Each device can be revoked on its own.
- Registration issues a recovery key that the user stores. There is no password reset.
- The server sends email through SMTP: address verification at registration, approval of a new device, and security notifications (device added, device revoked, master password changed, recovery key used). It never sends a password reset.
- Without SMTP configured, the server stays safe: open registration is unavailable, users are created by an administrator, new devices are approved from an already signed-in device, and the panel shows that email notifications are off.
- Email content is localized in English and Hebrew using the user's language, through the localization system.
- Sign-in attempts are rate-limited, and security events are recorded in the activity log.

## Admin panel

- The look and feel follow the Pay admin panel: layout, typography (Heebo), component patterns, light and dark themes, and Hebrew RTL and English LTR.
- Tildeck has its own brand mark and colors, not purple. Pay's brand is not reused.
- Pay's design and code may be reused. Shlomi confirmed that Pay code may be released under Apache-2.0. Reused code is adapted to Tildeck's brand and domain, and Pay-specific parts (Cardcom, CRM, Entra) are not carried over.
- Screens for the first release: first-run setup, dashboard, users, devices, settings, and activity log.

## Planned repository root

| Root file | Git tracking policy | Why this exact root location is required | Status |
|---|---|---|---|
| `README.md` | Tracked | GitHub and contributor convention | Exists |
| `AGENTS.md` | Tracked | Agent instruction discovery convention | Exists |
| `LICENSE` | Tracked | GitHub license detection and Apache-2.0 convention | Exists |
| `CHANGELOG.md` | Tracked | Release workflow and contributor convention | Exists |
| `.gitignore` | Tracked | Git reads repository-wide rules from the root | Exists |
| `.gitattributes` | Tracked | Git reads it from the root; enforces LF for scripts and text files | Exists |
| `VERSION` | Tracked | The single product version shared by the client, server, and panel; read by the release workflow and the image builds. No single ecosystem directory owns it. | Exists |
| `docker-compose.yml` | Tracked | Production deployment file, run by operators from the repository root | Exists |
| `docker-compose-dev.yml` | Ignored (exact path in `.gitignore`) | Machine-local development Compose file required at the root by the Docker contract, used only by `scripts/local.sh` | Template exists at `docs/development/docker-compose-dev.example.yml`; the root copy is machine-local |
| `.env.example` | Tracked | Environment contract next to `docker-compose.yml` | Exists |
| `.env` | Ignored | Real operator values next to `docker-compose.yml`; never committed | Planned (machine-local) |

Everything else lives in purpose-specific directories: `app/pubspec.yaml` and `app/pubspec.lock` in `app/`, `server/pyproject.toml` and `server/uv.lock` in `server/`, `panel/package.json` and `panel/package-lock.json` in `panel/`, `SECURITY.md` and `CONTRIBUTING.md` in `.github/`, workflows and Dependabot in `.github/`, and scripts in `scripts/`.

## Containers

| Service | Runtime user | Health check | Persistent state | Bind-mounted host directory | Named-volume exception | Backup lifecycle |
|---|---|---|---|---|---|---|
| `server` (API and static admin panel) | Dedicated non-root user declared in the final image | A health check command in the image that calls the readiness endpoint, which checks database connectivity | None | None | None | Not applicable |
| `postgres` | `postgres` (the official image drops root before starting the database) | `pg_isready` against the application database | Database files, including settings and the activity log | Production: host directory set by an operator variable, writable by the container's `postgres` UID | Development only: a named volume, because `initdb` cannot set the required permissions on a bind mount of a Windows drive | `pg_dump` to a host directory; restore with `pg_restore` into a fresh database. Ordinary `down` keeps the data. Only the confirmed `nuke` operation removes it. |

**Docker rules that apply:**

- `docker-compose.yml` references published GHCR images. `docker-compose-dev.yml` references explicit development images such as `tildeck-server:dev`. Neither file contains `build:`, and a CI guard enforces this.
- Container runtime variables come from `.env` through `env_file`. Compose interpolation is limited to values Compose itself needs, such as the image tag and the host data directory.
- `.env.example` lists the bootstrap variables and the optional setting overrides, with placeholder values only.
- Logs go to stdout and stderr.
- The self-hosting guide documents PostgreSQL major upgrades with dump and restore before the first release.

## Foundation implementation plan

The foundation task builds infrastructure only. It includes minimal client, server, and panel shells because the workflows and CI need real artifacts to build and verify. It does not include product features.

| Order | Deliverable | Status | Acceptance criteria | Required verification |
|---|---|---|---|---|
| 1 | Repository baseline | Done, except `.env.example` which comes with deliverable 6 | `git init` with default branch `main`; `LICENSE` (Apache-2.0), `.gitignore`, `.gitattributes`, `CHANGELOG.md` with an `Unreleased` section, `VERSION`; root matches the table above | `git ls-files` matches the root inventory; `.env` and `docker-compose-dev.yml` are ignored and `.env.example` is tracked |
| 2 | Toolchain containers | Done for Flutter with the Android SDK, Node, and Python with `uv`; the remaining scripts and CI adopt them as they are written | Pinned Flutter-with-Android-SDK, Node, and Python-with-`uv` toolchain images, referenced by digest, used by all Bash scripts | The server, panel, and an Android APK build inside WSL with only Docker installed |
| 3 | Server shell and API contract | Done. Endpoints: `/api/health/live`, `/api/health/ready`, `/api/info` | FastAPI app in `server/` managed with `uv`; liveness and readiness endpoints; health check command; Alembic with an initial migration; the version from `VERSION`; settings registry and settings encryption adapted from Pay; exported `server/openapi.json` with the protocol version | pytest passes against a real PostgreSQL container; the image runs as non-root; the exported OpenAPI document matches the committed one |
| 4 | Admin panel shell | Done | Nuxt static app in `panel/` with English and Hebrew, RTL and LTR, light and dark themes, Heebo, and the Tildeck brand; served by the server | Lint and type checks pass; screenshots of the shell in English LTR and Hebrew RTL, light and dark, at desktop and mobile widths |
| 5 | Client shell | Done, except the Windows build (deliverable 8). Golden images in `app/test/goldens/` replace device screenshots | Flutter app in `app/` for Windows and Android with application ID `com.tildeck.app`; English and Hebrew localization with RTL; light and dark themes; Dart API client generated from `server/openapi.json` and a call to the server's version endpoint | `flutter analyze` and tests pass; screenshots on Android in English LTR and Hebrew RTL, light and dark |
| 6 | Docker definitions | Done | Multi-stage server `Dockerfile` with a non-root final stage that includes the built panel; `docker-compose.yml`; a documented way to create `docker-compose-dev.yml` on a new machine; `.env.example` | Both services report healthy; the application process UID is not 0; no `build:` in either Compose file |
| 7 | Local workflow | Done, including `apk` (debug APK into `out/`) and `contract` (re-export the OpenAPI document and regenerate the Dart client) | `scripts/local.sh` with `build`, `up`, `up -d`, `down`, `status`, and confirmed `nuke` | Stops on the first failed build; fails clearly when `docker-compose-dev.yml` is missing; `down` then `up` preserves database data; `status` shows healthy services and the running image identity |
| 8 | Windows client script | Done: builds and launches on Windows; the rendered window was not inspected (see current truth) | `scripts/windows.ps1` builds and runs the Windows desktop client using Flutter on Windows | Builds and launches the client shell on Windows; fails clearly when Flutter or Visual Studio build tools are missing |
| 9 | Verify workflow | Done locally; the CI run comes with deliverable 12 | `scripts/verify.sh` with full and changed-area modes: shell lint and format; Python lint, format, and pytest against a real PostgreSQL container; Dart format, analyze, and tests; panel lint, type checks, and build; Android build; server image build; OpenAPI and generated-client drift check; Hebrew guard; Compose `build:` guard | A full run passes locally in WSL and in CI with the same commands; temporary containers are removed |
| 10 | Try-PR workflow | Done locally (`--ref`); fetching a real pull request waits for the repository | `scripts/try-pr.sh <number>`, `status`, `restore`; disposable worktree; rebuilds only affected areas; restarts only the server container; snapshots the development database before applying PR migrations and restores it on `restore` | The running server image matches the fresh build; the checkout is untouched; the worktree and snapshot are cleaned up |
| 11 | Release workflow | Script done and exercised against a local origin; the publish workflow is written and linted, not yet run on GitHub | `scripts/release.sh` with a dry run and an explicit target; preflight, clean synchronized `main`, full verify, version bump, closed changelog, immutable tag; CI builds and publishes the APK, Windows package, and server image | The dry run changes nothing; no secrets printed; no tag force-push; no overwrite of a published version |
| 12 | Path-filtered CI | Written and linted; not yet run on GitHub | Change-detection job; area jobs for app, Windows build, server, panel, scripts, and guards; summary job; cancel superseded PR runs only; manual full run; weekly scheduled full sweep; least-privilege permissions; actions pinned by commit SHA | A docs-only PR skips build jobs and the summary job passes; a panel-only change skips app jobs |
| 13 | Dependency management | Done: lockfiles enforced by every install; Dependabot configuration validated | Committed `app/pubspec.lock`, `server/uv.lock`, and `panel/package-lock.json`; installs use them; weekly Dependabot for pub, uv, npm, GitHub Actions, and Docker, with minor and patch updates grouped | Dependabot configuration validates; CI fails on an out-of-date lockfile |
| 14 | GitHub configuration | Done for a private repository; branch rules, secret scanning, and private vulnerability reporting wait for the public switch | Organization `tildeck` created by Shlomi; repository with the approved visibility; default branch `main`; focused labels; issue templates; `SECURITY.md`; branch rules requiring the CI summary check; Dependabot and secret scanning enabled; Actions default token read-only | Settings reviewed with `gh` after creation |

Later product phases, each separately approved: security model document, local vault, SSH sessions, accounts and email, sync API, admin panel screens, SFTP.

## Product implementation plan

Approved by Shlomi on 2026-09-30: the working version is the full first-release scope. Each step is its own pull request with a green CI `summary` check, and ends with an APK and a Windows build for Shlomi to try; he judges the Android and Windows experience, which no automated check here can see.

| Order | Step | Status | Acceptance criteria | Required verification |
|---|---|---|---|---|
| 1 | Security model | Approved (2026-09-30) | `docs/security-model.md` defines keys, wrapping, records, accounts, devices, recovery, sync, and the admin panel's boundaries | Shlomi approves it |
| 2 | SSH sessions and terminal | Done in code and tests; waiting for Shlomi's try on his phone and on Windows | Connect with password or private key; sessions in tabs; host key verification with a clear changed-key warning; terminal always LTR; Android key bar (Esc, Tab, Ctrl, arrows); copy and paste | Tests against a pinned OpenSSH container; APK and Windows build tried by Shlomi |
| 3 | Local vault and hosts | Done in code and tests; waiting for Shlomi's try on Windows | Master password; hosts in groups; private keys and known host keys stored as encrypted records; auto-lock | Tests that no plaintext reaches storage; APK and Windows build |
| 4 | Accounts and email | Done on the server; the client uses it in step 5 | Registration by mode, email verification, pre-login, sign-in, new-device approval, recovery, security emails, rate limits, stable error codes | Server tests against PostgreSQL and an SMTP stub |
| 5 | End-to-end sync | Done; Shlomi registered and synced through his proxy (2026-10-01) | Pull and push with versions, conflicts, and tombstones; protocol check | Two clients converge in tests; Shlomi syncs his phone and Windows through his HTTPS proxy |
| 6 | Admin panel screens | Done; Shlomi set up an administrator (2026-10-01). Invitations added | First-run setup with a one-time token, administrator TOTP, users, devices, settings with environment locks, activity log | Panel screenshots in both languages and themes |
| 7 | SFTP | Done in code and tests; waiting for Shlomi's try | Browse, upload, and download over an open session | Tests against the OpenSSH container |

### Step 2 notes (2026-09-30)

- The client opens SSH sessions in tabs (`dartssh2` 4.1.0, `xterm` 4.0.0) with password or private key authentication (Ed25519, ECDSA, RSA; passphrase-protected keys). Credentials stay in memory for the session only; saved hosts and keys come with the vault (step 3).
- Host keys: the first connection shows the SHA-256 fingerprint and asks; a trusted key connects silently; a changed key blocks with a warning, where cancel is the default and replacing the key is a deliberate action. Trusted keys live in `known_hosts.json` in the app support directory until the vault takes them over as records.
- The terminal is always LTR, uses the bundled JetBrains Mono (SIL Open Font License), copies and pastes with Ctrl+Shift+C and Ctrl+Shift+V or a right click on desktop, and on Android shows a key bar (Esc, Tab, Ctrl latch, arrows, common symbols, copy, paste).
- Verification: `scripts/verify.sh --area app` starts a throwaway OpenSSH server (`openssh` in `scripts/toolchain/Dockerfile`), generates a password and two Ed25519 keys for the run, and runs integration tests against it: password and key sign-in, a wrong password, a key that needs its passphrase and a wrong passphrase, a changed host key refused, a closed port, and an interactive shell through the terminal. The same tests pass natively on Windows against the same server. Golden images cover the connect form (both languages and themes), the terminal with the key bar, the changed host key warning, and the sync server page.
- Found and fixed while testing: a refused changed host key was reported as an authentication failure, because the library surfaces the closed transport as an authentication abort.
- Confirmed by Shlomi on Windows after the fix: typing works (2026-09-30).
- Found by Shlomi on Windows: the terminal connected but accepted no typing. xterm 4.0.0 opens its keyboard connection without a view id, which Flutter's Windows embedder rejects since 3.44 (upstream pull requests #224, #228, #231, none merged). Fixed in the vendored copy; `app/test/terminal_input_test.dart` fails without the fix. The test binding accepts the call either way, which is why the earlier end-to-end typing test could not catch it.

### Step 3 notes (2026-09-30)

- The client opens with a master password. The first start creates the vault (at least 12 characters, not one of 1,188 common long passwords from the NCSC list in SecLists, a clear no-reset warning); later starts unlock it. A wrong password says only that it is wrong.
- The vault is `vault.json` in the app support directory: the vault id, the Argon2id parameters and salt, the wrapped vault key, and one record per entry with its id, version, tombstone flag, nonce, and ciphertext. It is written atomically; nothing in it is readable without the master password.
- Saved hosts (with a group name, host, port, username, and either a saved password, a password asked at each connection, or a key), private keys, and trusted host keys are records. Host keys trusted before the vault existed are imported from the old `known_hosts.json` once, and the file is removed.
- The vault locks after 15 minutes without a key press or a touch, and from the lock button. Open sessions keep running behind the lock screen and reappear on unlock; nothing of the vault is shown or focusable while locked, and every screen or dialog opened above the vault (a host editor with a typed password, the keys list, a password prompt) closes when it locks. The last point was a bug found in review before merge; `vault_ui_test` covers it by firing the 15-minute timer with an editor open.
- Measured: one Argon2id derivation (ops 3, 64 MiB) takes about 85 ms in the Linux container and 90 ms natively on Windows on this machine; phones will be slower and are measured when Shlomi tries Android.
- Tests: the vault file contains no plaintext; a changed ciphertext, a ciphertext moved to another record, and an old ciphertext replayed under a newer version are all detected and reported without being dropped; deletions keep tombstones; host keys in the vault; the password rules; and the whole flow through the interface (create, save a host, lock, wrong password, unlock). Golden images add the hosts list, the create screen, and the unlock screen.
- Groups are a name on each host rather than records of their own (the security model says so); renaming a group means editing its hosts.
- Fixed on 2026-10-01: typing on the Android soft keyboard is neither a hardware key event nor a touch, so a long stretch of typing in a terminal did not reset the idle timer and the vault could lock mid-session. Terminal input now reports activity to the lock timer; `idle_lock_test` covers it.
- For product step 5: the local vault file is the only record of the highest version seen per record; a pull from the server must never lower a stored version.

### Step 5 notes (2026-09-30)

- The server stores encrypted records with a version per record and a revision per account: `GET /api/sync/records?since=` pulls in revision order and in pages of 1,000, and `POST /api/sync/records` accepts up to 500 changes, each only as exactly the next version, and answers the others as conflicts with the server's current record. Tombstones carry no content. Server tests cover versions, conflicts, tombstones, paging, isolation between accounts, and revoked devices against PostgreSQL.
- The vault file moved to format 2: a dirty flag per record, the pull cursor, and this device's account (server, email, device id and name, device token) sealed under the vault key. A format 1 file loads as never synced. This replaces platform secure storage for the device token; see the security model's clarification, which needs Shlomi's confirmation.
- The client syncs after unlock, two seconds after a local change, every minute while the vault is open, and on "Sync now": it pulls until it is current, then pushes every dirty record, resolving conflicts by the newer `modified_at` (an edit wins against a deletion) and pushing a local winner again in the same sync.
- The sync screen (the cloud button) connects to a server: create an account with the vault on this device, which shows the recovery key once and continues only after the user confirms saving it; or sign in. Signed in, it shows the sync status, "Sync now", a link to resend the confirmation email when the address is not confirmed, the account's devices with Approve for a waiting one and Remove for the others, and sign out. On a device without a vault, the create screen offers "I already have a sync account": sign in, wait for approval (the screen asks every five seconds and continues by itself), and the vault arrives.
- Tests: two vaults converge through an in-memory server that follows the server's contract (`app/test/fake_sync_server.dart`): additions, edits, deletions, both directions of a conflict, an edit against a deletion, an edit made while its earlier version is on its way, a vault uploaded after local use, a damaged server record, a replayed older version, paging, and the reported problems. `sync_ui_test` runs the whole flow through the interface: register with a recovery key, a second device signs in, waits, is approved, and receives the hosts; and a signed-in device approves a waiting one. The fake is not the real server: the contract area checks the generated client against the server's OpenAPI document, but not the fake's behavior. Golden images add the sync screens (connect, signed in with a waiting device, the recovery key, waiting for approval) in English light and Hebrew dark, replacing the sync server page.
- Found and fixed while testing: after registration, the sync screen switched to the signed-in view before the recovery key could be shown, so the key was lost. The flow test covers it.
- Known leftovers: recovery and changing the master password were added on 2026-10-01 (below); the server trusts forwarded client addresses from any peer (`--forwarded-allow-ips *`), so the per-address sign-in limit relies on the proxy overwriting `X-Forwarded-For`.

- Added on 2026-10-01: changing the master password (the password button in the top bar; with an account, other devices are signed out unless the user keeps them) and recovery with the recovery key ("Forgot your master password?" on the unlock screen and on sign-in). Recovery checks that a vault already on the device is the account's before anything changes on the server, because it signs out every other device. A device that signs in after the password changed elsewhere takes the new wrapped key, so its own vault file opens with the new password. Found while testing: a sync requested while one ran returned at once instead of waiting for the queued run; it now waits.

### Step 6 notes (2026-10-01)

- The admin API lives under `/api/admin` and stays out of `server/openapi.json`: only the panel, served by the same server, calls it.
- First run: while no administrator exists, each server start prints a new one-time setup token to its log (`docker compose logs server`). Setup takes the token, a username, and a password of at least 12 characters, returns a new TOTP secret with an `otpauth://` address and its QR code, and creates the administrator only once a code from that secret is confirmed. After that, setup answers `setup_not_needed`.
- Sign-in takes the password and a TOTP code; a code is accepted once (the last used time step is stored) with one step of clock drift either way. Failures look the same whatever was wrong, are rate-limited per address and per username, and are logged. Sessions live on the server and end after 30 idle minutes or 12 hours; the cookie is `HttpOnly`, `Secure`, `SameSite=Strict`, limited to `/api/admin`, and every change needs the session's `X-CSRF-Token`.
- Administrators list users with metadata only (email, confirmation, created, last seen, device count, record count, storage), disable and enable an account (its devices stop syncing at once), delete it with its devices and records, and revoke a device (the user gets the same security email as when removing it themselves). Settings show where each value comes from; environment values lock their field; secret values never leave the server. The activity log pages newest first. Every administrative action is logged with the administrator's name.
- The panel has first-run setup (token, name and password, then the TOTP enrollment with a QR code and the key for manual entry), sign-in, an overview, users (a table, and cards on narrow screens), one user with its devices and the disable, enable, delete, and remove-device actions behind a confirmation, settings grouped by purpose with their origin and lock, and the activity log with paging. Every page but setup and sign-in needs a session; a server without administrators sends every page to setup. Strings are in English and Hebrew.
- Verified in a real browser against the dev server: setup with the logged token and a code computed from the enrolled key, then a setting changed from the settings page (saved, logged as an administrator action) and an invalid value refused with its message. Playwright screenshots of every page in English LTR light and Hebrew RTL dark, at 1280x800 and 390x844, including the delete confirmation and the mobile menu; users come from sample data served inside the browser, so nothing was written for them. The dev server was returned to its state before the test (no administrator, no stored setting); the activity log keeps the entries of the test, as it is append-only.
- Found and fixed in the browser: the QR code did not render, because the inline SVG had no namespace; it is now a data URI image, and no server markup reaches the page as HTML.
- Invitations (decided by Shlomi on 2026-10-01): an administrator invites an email address from the Invitations page; the code is shown once and, with email configured, sent to the address in the panel's language. Registering with it works in the invite and open modes, needs no SMTP, and confirms the address, so the new device syncs at once. The app's account form has an optional invitation code field. Server tests cover one address, one use, a wrong address, a cancelled and an expired code, and the email.
- The settings page saves with one button (after Shlomi's review): a bar appears with unsaved changes and saves them in one transaction; a refused value saves nothing and shows its reason under its field.
- Not in this step: managing further administrators.

### Step 7 notes (2026-10-01)

- A connected session has a Files button next to the tabs. It opens the server's files over SFTP on the session's own connection: no second sign-in. The browser starts in the user's home folder, lists folders first, follows links to folders, and shows sizes and dates; the path and names are LTR in both languages.
- Tapping a file downloads it. On Windows it goes straight into the Downloads folder as it arrives, never over an existing file ("name (2).ext"), with characters Windows refuses in a name replaced; on Android it goes through the system's save dialog. Upload sends one or more chosen files into the current folder and never replaces a file there; New folder creates one. Transfers show their progress and how they ended. File choosing uses `file_picker` 13.1.0 (MIT).
- Tests: `sftp_integration_test` runs against the OpenSSH container of `verify.sh --area app`: the home folder, a new folder, a 300 KB upload in chunks and its download byte for byte, an upload refused over an existing file, a missing folder, and a folder without permission. `files_ui_test` covers the screen: a folder opens, a file downloads to where the user keeps files, an upload goes to the folder. Golden images show the screen in English and Hebrew.

### Step 4 notes (2026-09-30)

- The server API for accounts and devices (`/api/account/*`, `/api/devices/*`, protocol header required): pre-login, registration, sign-in, new-device approval (from another device or by an emailed link) and claiming, device listing and revocation, verification email resend, master password change, and recovery with the recovery key. Keys and wraps are opaque base64; the server stores Argon2id hashes (`argon2-cffi`) of the authentication and recovery keys and SHA-256 hashes of every token.
- The client does not use these endpoints yet: account screens come with sync in step 5.
- Pre-login answers an unknown address with a stable salt derived from `CONFIG_ENCRYPTION_KEY`, so it does not reveal which accounts exist. Registration does reveal an address that already has an account (`email_taken`); it is rate-limited per client address.
- Registration modes: `closed` refuses; `open` needs SMTP and `PUBLIC_URL`; `invite` refuses with `registration_invite_required` until the admin panel creates invitations (step 6). Accounts without SMTP are created by an administrator (step 6).
- Emails (verification, approval, device added, device removed, password changed, recovery used) are plain text in the account's language from `server/app/locales/`. The email link pages live under `/links/`, outside the API contract; approving a device needs a button press, because mail scanners open links on their own.
- Rate limits count in memory per server process and reset on a restart.
- The security model gained a clarification of how an approved device collects its vault key (a one-time claim token held only by the pending device); the approved decisions are unchanged.
- Tests (33 in the server area): the protocol header, pre-login, registration modes, verification links (single use, expiring), sign-in failures that look the same for known and unknown addresses, a pending device that cannot collect before approval or with a wrong claim token, an approval link that approves only on the button, re-sign-in of an approved device, revocation, idle expiry, password change signing out other devices, recovery, the rate limit, Hebrew emails, no key or wrap in any email, and delivery through a real SMTP server (without TLS: STARTTLS and TLS are not exercised, because the test server has no certificate).
- Contract rules learned from the Dart generator (CI caught it: the generated client did not compile): no response unions (sign-in returns one `SigninResult` with a `status`), no `Literal` fields with a default value, and no FastAPI validation error schema. Malformed requests answer `422` with the stable `invalid_request` error body, and the contract documents that body instead.
- To try the account flow end to end later, the server needs an SMTP provider configured (in `.env` or the panel) and `PUBLIC_URL` set to the address behind the HTTPS proxy.

## Termius parity plan

Approved by Shlomi on 2026-10-01, after the proof of concept (steps 1 to 7) was tried and accepted: Tildeck takes on every capability Termius offers, built our own way (no Termius code, design, or brand). Order is ours to choose; each piece is a pull request merged on a green CI `summary` check.

| Stage | Scope | Status |
|---|---|---|
| 1 | Daily terminal work: snippets (run here, on several hosts, at session start), host tags and search, settings inherited from a group, environment variables, terminal themes and font size, search in the terminal, tab names, split view on desktop, command and connection history | Snippets, host tags and search, group settings, environment variables, terminal themes and font size, search in the terminal, tab names, connection history, autocomplete, and split view done |
| 2 | Connectivity: local, remote, and dynamic (SOCKS) port forwarding, jump hosts, agent forwarding, SOCKS and HTTP proxies, Telnet, a local terminal on Windows | Done: port forwarding, jump hosts, agent forwarding, proxies, Telnet, and a local terminal on the desktop |
| 3 | Keys and sign-in: key generation (Ed25519, RSA), import and export, SSH certificates, two-factor sign-in for user accounts, biometric unlock (requested by Shlomi; security model addition first) | Key generation, import, export, and SSH certificates done; two-factor sign-in and biometric unlock next |
| 4 | SFTP: side-by-side local and remote panes, rename, delete, permissions, drag and drop, editing a file in place | Planned |
| Later | Mosh (no Dart implementation), FIDO2 keys (not in `dartssh2`), serial, AI autocomplete (needs a provider and a privacy decision), cloud imports (AWS, DigitalOcean, Azure), Ansible, SAML SSO | Not started |
| Not now | Teams: shared and multiple vaults, access control, shared session logs (Shlomi, 2026-10-01: not now, maybe later) | Deferred |

### Snippets (2026-10-01)

- A snippet is a vault record (name and command), so it is encrypted and syncs like a host. The Snippets page (the code button on the hosts list) adds, edits, and deletes them.
- In a connected session, the Snippets button next to the tabs runs a snippet there, or opens a session on each chosen host and runs it in each. A host can have a startup snippet that runs as soon as its shell opens. Each line is sent as typed, followed by Enter.
- A record of a type this version does not know (from a newer version, through sync) is now kept untouched and hidden instead of being reported as damaged.
- Tests: snippets and startup snippets kept encrypted in the vault; an unknown record type kept and not damaged; against the OpenSSH container, a startup snippet runs when the shell opens and a two-line snippet runs line by line. Golden images of the Snippets page in English and Hebrew.

### Hosts: tags, search, group settings, environment variables (2026-10-01)

- Hosts have tags. The hosts list has a search box that matches every typed word against the name, address, user, group, and tags.
- A group (hosts still name their group) can have settings: a username, a key, a startup snippet, and environment variables. A host takes them wherever it leaves its own field empty, and the host's own value always wins; group and host environment variables merge, host first. The settings button next to a group name edits them.
- Environment variables are requested for the shell when the session opens. The server applies only names its `AcceptEnv` setting allows; the test server in `verify.sh --area app` allows `TILDECK_*` for its test.
- Tests: search, the NAME=value format, inheritance from a group with the host's own values winning, and against the OpenSSH container a variable that reaches the shell. Golden images of the hosts list with tags and of the group settings page.

### Terminal appearance, search, and tab names (2026-10-01)

- Ten color schemes (Tildeck Dark and Light, Solarized Dark and Light, Nord, Gruvbox Dark, One Dark, Monokai, Dracula, GitHub Light, with their published palettes) and a font size from 9 to 28, on the Terminal appearance page with a live preview. Ctrl and + or - changes the size in a terminal, Ctrl and 0 restores it. Both are kept in one preferences record in the vault, so every device follows.
- Search in the terminal (the search button, or Ctrl+Shift+F): every match in the scrollback, case-insensitive, highlighted translucently; Enter and Shift+Enter or the arrows step through them, Escape closes.
- A tab can be renamed with a double click or a long press; an empty name brings back the connection.
- The top bar keeps Lock and Sync; terminal appearance, the master password, the language, and the theme moved into a More menu. A golden image caught the bar overflowing a phone's width by 35 pixels once the appearance button was added.
- The UI tests' waits now allow 20 seconds: with more test files running at once, Argon2id took longer than the old 6 seconds.

### Connection history (2026-10-01)

- Every session is written to the history when it connects or fails, and its end time when it closes: the saved host, user@host, the times, the device, and whether it failed. The records are encrypted and synced, so the history covers every device, like Termius's session logs. It keeps the newest 200.
- The hosts list shows the five most recent saved hosts for one-tap reconnecting, and the History page (the clock button) lists every connection with its length; tapping one with a saved host connects again.
- Command history is not recorded: the app cannot tell a typed command from a password typed at a prompt (`sudo`, `passwd`) whose echo the server turned off, so recording keystrokes would store and sync passwords. Shlomi chose the Termius approach instead (2026-10-01): see Autocomplete.
- Tests: a session logged on connect and closed off with its length, a failed connection, and the 200 limit. A golden image of the History page.

### Autocomplete (2026-10-01)

- As in Termius, suggestions come from the server's own history, read after connecting over a separate exec channel (bash, zsh, and fish history files) and never stored or synced here, and from the user's snippets. A server that refuses exec channels simply gets no suggestions; the session goes on.
- The line being typed is followed in memory only, to filter the suggestions, and forgotten at Enter. Anything that changes the line unseen (arrow keys, history recall, Tab completion) stops the suggestions until the next line.
- A bar above the key bar shows up to four: snippets, then commands that start with the typed text, then ones that contain it. A tap completes the line; the user still presses Enter.
- At a password prompt (sudo, su, passphrases), the bar offers the password the session signed in with; nothing typed is recorded.
- A switch on the Terminal appearance page turns suggestions off; it is on by default.
- Tests: bash, zsh, and fish history parsing; ranking with snippets; following the typed line through Backspace, Ctrl+U, Enter, arrows, and Tab; completion input; password prompt recognition. Against the OpenSSH container: the history read from the server, a line completed from it and run, and a real password prompt answered with the session's password.

### Split view (2026-10-01)

- On a screen at least 840 pixels wide with two or more sessions, the Split button shows the selected session and another one side by side. A click on the other side makes it the active one (its tab is selected and the bar shows its actions); the button returns to a single view, and closing a session keeps the split pointing at the right one.
- Test: two sessions split, the active side changing on a click, and back to one.

### Port forwarding (2026-10-01)

- Rules are vault records (`port_forward`), encrypted and synced like hosts. Each runs through a saved host, with that host's group settings, and opens its own connection to it, so it works with or without a terminal open.
- Local (like `ssh -L`): listens on this device and connects from the server to the destination. Remote (like `ssh -R`): listens on the server and connects from this device to the destination. Dynamic (like `ssh -D`): a SOCKS5 proxy on this device whose connections leave from the server.
- The listen address defaults to 127.0.0.1, so a rule serves only this device unless the user types another address.
- The Port forwarding page, opened from the hosts screen, turns rules on and off with a switch and shows the address and the connection count, or why a rule could not start: the host could not be reached, the port is taken, or the server refused to listen. A dropped connection turns the rule off. Running rules stop when the app closes.
- Tests: rules saved and read back; a rule added in the editor with port validation; a start failure shown. Against the OpenSSH container: a local forward reaching the server's own sshd, a remote forward answered by a service on this device, a SOCKS5 handshake and connection, and a taken port reported. The test server now allows TCP forwarding.

### Jump hosts (2026-10-01)

- A host may connect through another saved host (like `ssh -J`), set in the host editor as "Connect through". A group may set one for its hosts; a host's own choice wins, and the jump host itself connects directly. A jump host with its own jump host makes a chain.
- The connection to the target is tunneled inside the connection to the jump host (a direct-tcpip channel), so the target's address is as the jump host sees it. Each host key is checked under its own address, and closing the session closes the tunnel under it.
- The editor offers only hosts whose own chain does not lead back, so a loop cannot be chosen; one made anyway by edits on two devices ends the chain where it repeats.
- A failure at a jump host names it: "At deploy@bastion: the server rejected the username or the credentials."
- Tests: chains, group inheritance, loop-free choices, and loops ending. Against the OpenSSH container, which is its own jump host: one hop, two hops, closing both connections together, a failure at the jump host named, and a target the jump host cannot reach.

### Agent forwarding (2026-10-01)

- A switch per host, off by default, lets the server use the vault's keys while connected (like `ssh -A`), for example to pull from Git or sign in onward. The client answers the server's agent requests itself; the keys never leave the device. Keys whose passphrase is not saved are left out.
- The switch explains the risk: anyone with root on the server can use the keys during the session.
- Only the host that asks for it gets the agent, not its jump hosts.
- Session requests are pipelined, as ssh(1) sends them: a refused environment variable, agent forwarding, or pty is skipped, and only a refused shell or command fails the session. Before this, a variable outside the server's AcceptEnv failed the whole session.
- Tests: the agent offered only when chosen; a refused environment variable no longer stops the shell (fails on the old behavior). Against the OpenSSH container, which now allows agent forwarding: the server signs in to itself with nothing but the forwarded key, and without the switch it has no agent and cannot.

### Proxies (2026-10-01)

- A proxy is a vault record (`proxy`): SOCKS5 or HTTP CONNECT, with a username and password only if it asks for them. A host or a group chooses one from the host or group editor, which also adds and edits proxies; a host's own choice wins.
- The proxy is used by the hop that connects directly. Through jump hosts, that is the first one: the proxy carries the connection to it, and the rest goes inside SSH.
- The target's name goes to the proxy unresolved (SOCKS5 by name, HTTP CONNECT by authority), so names only the proxy can resolve work.
- Failures name the proxy when it is the proxy: unreachable, or a refused or missing password. A target the proxy cannot reach is reported as the target being unreachable.
- Tests: both protocols against small proxies in the test, with and without a password: relaying both ways including bytes that arrive with the handshake, a wrong or missing password, a target the proxy cannot reach, a proxy that is not there. Against the OpenSSH container: SSH through each kind with a password, a refused proxy password named, and the proxy used only for the first hop through a jump host. A proxy added from the host editor, chosen, and used to connect.

### Telnet (2026-10-01)

- A host is SSH or Telnet, chosen in the host editor (Telnet moves a default port 22 to 23). The editor warns that Telnet is not encrypted, makes the username optional, and hides what only SSH has: keys, environment variables, agent forwarding, a startup snippet. Files are offered only in SSH sessions.
- Telnet signs in inside the terminal. A saved password is offered at the device's password prompt, as in SSH sessions; nothing is typed for the user.
- The connection opens the way SSH does, so jump hosts and proxies work for Telnet too.
- The client offers its terminal type (TTYPE) and window size (NAWS, sent again on every resize), lets the server echo and suppress go-ahead, and refuses every other option, answering only on a change so negotiation cannot loop. Byte 255 is doubled and a bare CR is sent as CR NUL (RFC 854).
- `scripts/verify.sh --area app` also starts BusyBox telnetd (`telnet` in `scripts/toolchain/Dockerfile`), which gives a shell without signing in.
- Tests: negotiation against a fake server (supported and refused options, no loops, terminal type, window size with a 255 in it, a command split across reads, typing escaped, the end of the connection). Against BusyBox telnetd: a shell with the window size it was told, again after a resize, Telnet through an SSH jump host, and a closed port. BusyBox does not ask for the terminal type, so that part is covered by the fake server only.

### Local terminal (2026-10-01)

- On the desktop, a terminal button on the hosts screen opens a local shell in a tab, like a session. On Windows it offers the shells it finds: PowerShell 7 (on PATH or where it installs), Windows PowerShell, Command Prompt, and WSL; elsewhere the user's login shell. Phones have none.
- The shell runs in a pseudo-terminal through `flutter_pty` (ConPTY on Windows), started in the user's home folder with the whole environment (the package alone copies only a few variables, too few for Windows shells), and resized with the terminal.
- A local shell is not a server: it stays out of the synced connection history, and offers no files or server history.
- `scripts/windows.ps1 test` runs the Windows-only tests in `app/integration_test/`, and the Windows CI job runs them after the build.
- Tests: shell detection on Windows (order, PATH and install folder, letter case, missing ones) and elsewhere; the hosts screen opening the chosen shell, and no button on a phone. On Windows over ConPTY: Windows PowerShell answering, in the home folder, at the terminal width and again after a resize, and ending on `exit`; Command Prompt seeing the whole environment.

### Keys (2026-10-01)

- The Keys page generates a key (Ed25519 by default, made with libsodium; RSA 4096 for old servers, made with pointycastle off the UI thread) or imports one, pasted or from a file. A key that cannot be read, or whose passphrase is wrong, is refused when it is saved, with a message, instead of failing later at connect time.
- Each key shows its type and SHA256 fingerprint, as `ssh-keygen -l` does. They and the public key line are read once when the key is saved and kept in the record, so the list never decrypts keys; keys saved before this are read once when the list shows them.
- Per key: copy the public key; install it on a saved host (like `ssh-copy-id`: it signs in the way that host already does and adds the line to `~/.ssh/authorized_keys` once, creating the folder and file with the modes sshd requires); export the private key to a file, protected by a passphrase in OpenSSH's own format (bcrypt and AES), to the Downloads folder on the desktop and through the save dialog on Android.
- The host editor can generate a key as well as import one.
- The public key's comment is reduced to characters that need no shell quoting, and the install command refuses a line with quotes or line breaks.
- Tests: generation, reading, fingerprints, export with and without a passphrase, refusing what is not a key, and the install command's quoting. On the Keys page: generate, copy the public key, export with a passphrase, and import from a file that needs its passphrase. Against the OpenSSH container, for Ed25519 and RSA 4096: the new key refused before, installed with the password (twice, kept once), then signing in alone; `ssh-keygen -lf` showing the same fingerprint; and `ssh-keygen -y` opening the exported file with its passphrase and refusing a wrong one.

### SSH certificates (2026-10-02)

- A key may carry an OpenSSH user certificate (its `-cert.pub` line), added from the key's menu by pasting it or from the file. A certificate that is not a user certificate, or is for another key, is refused when it is added.
- When the key signs in, the certificate is offered first and the bare key after it, so a server that does not trust the certificate's authority may still accept the key. The certificate's algorithm follows the key's signature (an RSA key, which signs with rsa-sha2-256, offers rsa-sha2-256-cert-v01).
- The Keys page shows who a certificate is for and until when, and marks an expired one.
- The test server now trusts a test authority whose key the account can sign with, and turns off OpenSSH's penalties for failed sign-ins (the tests fail some on purpose, all from one address).
- Tests: reading certificates (principals, validity, the certified key, refusing host certificates and broken ones). On the Keys page: a certificate for another key refused, the key's own kept and shown. Against the OpenSSH container, for Ed25519 and RSA 4096: a key in no authorized_keys refused alone and signing in with its certificate; a certificate for another user, and an expired one, refused.

### Files: operations and a standalone browser (2026-10-02)

- Each file or folder has a menu: download, rename (the name offered with its stem selected; never over another entry, and a name, not a path), permissions (owner, group, and others; read, write, and run; with the octal value and the ls form), copy the path, and delete.
- Deleting asks first, saying whether a folder goes with everything in it: files on a server have no undo. A folder is deleted depth first; a link is removed, never followed.
- The list shows each entry's permissions. A View menu shows or hides dotfiles (hidden by default) and sorts by name, size (largest first), or date (newest first), folders always first. Tapping the path opens a folder by path, absolute or relative.
- A host's menu opens its files directly, on a connection of their own that closes with the page: no terminal needed. A failure to connect shows the same message a session would.
- Tests: against the OpenSSH container, on a tree made by the shell: hidden files, each sort, going to a path, renaming (and refusing to replace or to take a path), permissions read back by `stat`, deleting a link without its target, and deleting a folder tree. On the page: rename with the stem selected, permissions from 644 to 664, copy the path, and delete after asking, with a cancel deleting nothing.

### Files: editing text on the server (2026-10-02)

- A file's menu offers Edit: the file opens in a monospace editor, left to right in either language, and Save writes it back over SFTP. The title marks unsaved changes, and leaving with them asks first, since they exist nowhere else.
- Saving first checks the file's size and modification time against the ones it was opened with. If someone changed it on the server meanwhile, it says so and saves only when asked to.
- Files with Windows line ends are edited with plain ones and saved with Windows ones again.
- Only UTF-8 text up to 2 MB opens: a larger file, a file with a NUL byte, or one in another encoding is refused with a message to download it instead, so nothing is mangled.
- Tests: against the OpenSSH container: a CRLF file edited and saved with its line ends, a change by someone else refused then saved over when asked, and a large, a binary, and a Latin-1 file refused. On the page: saving after a change on the server asks; leaving unsaved asks, and keeping or discarding works. Golden: the editor in both languages.

### Files: folders, several at once, and cancelling (2026-10-02)

- A running transfer has a cancel button. A cancelled or failed download leaves no partial file here, and a cancelled or failed upload leaves no partial file or folder on the server.
- On the desktop, a folder downloads with everything in it (into a new folder in Downloads, never over one that exists) and a local folder uploads into the current one (never over an existing entry). A folder transfer is one entry with the overall progress and a count of files. Links and devices are left out of a folder copy; empty folders are kept. Android's file picker has no folder access, so folders move only on the desktop.
- A long press selects; while selecting, a tap selects too. The selection is downloaded, or deleted after asking, together.
- Tests: against the OpenSSH container: a folder tree (with an empty folder) down and up again, identical, and refused over an existing folder; a download and an endless upload cancelled midway, leaving nothing behind. On the page: selecting by long press and tap, deleting the selection after asking, and cancelling a running transfer.
### Known hosts (2026-10-02)

- The Keys page opens Known hosts: every server whose key the vault trusts, with the key type and the whole fingerprint, searchable once there are more than a few. Removing one (with undo) makes the next connection ask again, as for a new server.
- Tests: the list (port 22 not written), and a removed key checked as unknown, then trusted again after undo. Golden: the page in both languages.

### Desktop layout: the shell (2026-10-02)

- From a window 900 pixels wide, the app lays out as a desktop app: a fixed sidebar with the vault's sections (hosts, keys, known hosts, port forwarding, snippets, history) and the app's settings (terminal appearance, sync, master password), with lock, theme, and language at its foot. Each section opens in place, with no page over the sidebar and no way back to take; the session tabs sit above the content. The layout follows the window's width, not the operating system: a wide tablet gets it, a narrow window gets the phone layout, which is unchanged.
- Pages that closed themselves when done (the history after reconnecting, the password change after saving) now close only when they were opened over another page, so they can sit in a section.
- Tests: every section opens in place from the sidebar, the hosts list drops the buttons the sidebar has, and a narrow window keeps the phone layout. Goldens: the desktop hosts and keys sections in both languages.

## Required workflow contracts

The four Bash scripts run in WSL with `#!/usr/bin/env bash`, LF line endings, and executable file modes. Each resolves the repository root from its own location.

**Windows exception.** Flutter can build the Windows desktop client only on Windows. At Shlomi's request, `scripts/windows.ps1` builds and runs it locally, and CI builds it on a Windows runner. This is the only non-Bash script.

- **`scripts/local.sh`** manages the development stack (`server` and `postgres`) through `docker-compose-dev.yml` only. It builds the panel and the server development image explicitly before changing the running stack, and can build a debug Android APK. It removes development data only through the confirmed `nuke` operation.
- **`scripts/verify.sh`** is the single entry point used locally, in CI, and by release. It supports a full sweep and a changed-area mode.
- **`scripts/try-pr.sh`** tests a pull request in a disposable worktree. For server or panel changes it rebuilds and restarts only the server against the existing development database, after taking a database snapshot. For client changes it builds an APK and reports its path. It never merges, pushes, or edits the user's checkout.
- **`scripts/release.sh`** prepares the release commit and immutable tag after a full verify run and requires an explicit target. Publication happens in the tagged CI run. Merge and release stay separate.

## Implementation decisions

Recorded during the foundation implementation, on 2026-09-28.

- **One image builds the panel.** The panel has no Dockerfile of its own. `server/Dockerfile` builds it from a named build context (`--build-context panel=./panel`) in the stages `panel-deps`, `panel-source`, `panel-check` (lint and type checks), and `panel-build`; the `runtime` stage copies `/panel/.output/public` to `/app/panel`. The panel provides the npm scripts `lint`, `typecheck`, and `generate`, and a committed `package-lock.json`.
- **Panel serving.** `server/app/panel.py` serves the static panel for GET and HEAD with a single-page-app fallback; `/api` and `/api/*` never fall back. Hashed assets under `/_nuxt/` are cached as immutable, everything else is revalidated.
- **Health endpoints.** `/api/health/live`, `/api/health/ready` (the image health check; includes the database), and `/api/info` (name, version, protocol version).
- **PostgreSQL 18.** `postgres:18`, digest resolved on 2026-09-28. PostgreSQL 18 images keep their data under `/var/lib/postgresql` (a versioned subdirectory), so both Compose files mount there, not at `/var/lib/postgresql/data`.
- **Development Compose template.** `docs/development/docker-compose-dev.example.yml` is copied by each developer to the ignored root `docker-compose-dev.yml`. It publishes the server on `127.0.0.1:8280` (8280 keeps it clear of Pay's development ports) and keeps the database in the named volume `tildeck-db-data`.
- **Production Compose.** No reverse proxy is bundled (TLS termination is still deferred). The server is published on `TILDECK_BIND:TILDECK_PORT`, defaulting to `127.0.0.1:8080` for a proxy on the same host. `APP_ENV` is forced to `production` in the file. The server runs with a read-only root filesystem and no capabilities; PostgreSQL gets back only the five capabilities its entrypoint needs.
- **Runtime UID check.** `scripts/local.sh` checks the UID of the container's PID 1 (from `/proc/1/status`), not the user of a `docker exec` session, which is root in the PostgreSQL image even though the database runs as `postgres`.
- **Panel lockfile.** The first `panel/package-lock.json` was seeded from Pay's lock (the same dependency set) because a fresh resolution on 2026-09-28 fails: vite 8.3 requires esbuild 0.27 or later as an optional peer, while `@intlify/bundle-utils` (through `@nuxtjs/i18n`) pins esbuild 0.25. Dependabot will hit the same conflict until `@nuxtjs/i18n` catches up.
- **Panel language.** English is the default and the fallback; the browser language is detected once and stored in the `tildeck_lang` cookie. The language switch shows the other language's own name, read from that language's locale file, so Hebrew text stays inside the allowed locale files.
- **Other pinned images, resolved for later deliverables:** `koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d`, `mvdan/shfmt:v3.12.0@sha256:307d265ffd25ce832899ae17c93ed5062fc3375c514bba8f52cbf52792735c4d`.
- **Dart API client.** Generated by OpenAPI Generator (`openapitools/openapi-generator-cli` v7.25.0, generator `dart`) into the path package `app/packages/tildeck_api`, which the app depends on. The generator's ignore file in that package drops its CI and README boilerplate. It handles the OpenAPI 3.1 document (typed models, enums for the stable error codes); a connection failure surfaces as an `ApiException` with an inner cause.
- **Toolchain pins.** `scripts/toolchain/Dockerfile` is never built. `scripts/lib/common.sh` reads its `FROM` lines by stage name so every script and CI job uses the same image, and it is a Dockerfile so Dependabot updates it. The Flutter container keeps pub, Gradle, NDK, and CMake caches in named volumes (`tildeck-pub-cache`, `tildeck-gradle-cache`, `tildeck-android-ndk`, `tildeck-android-cmake`); without them every Android build downloads the NDK again (8.5 minutes instead of 3.5).
- **Client screenshots.** No Android emulator runs in WSL. Flutter golden tests render the shell on a 412x915 phone in English LTR and Hebrew RTL, light and dark, with the bundled font, and the committed images in `app/test/goldens/` are the reviewable screenshots.
- **Client font.** Heebo (SIL Open Font License, `app/assets/fonts/OFL.txt`) is bundled as static 400, 500, 700, and 800 instances cut from the Google Fonts variable font with fonttools, so Hebrew renders the same on every device and in tests. Material's default letter spacing is removed because it pulls Hebrew letters apart.
- **Client localization.** `flutter gen-l10n` output (`app/lib/l10n/app_localizations*.dart`) is generated on every pub get and build and is not committed; it would also carry Hebrew outside the allowed locale file. The language switch shows the other language's own name from its own ARB file.
- **Android identity.** `com.tildeck.app`, label `Tildeck`. The INTERNET permission is declared in the main manifest, because only debug builds get it from the debug manifest.
- **Verify areas.** `server`, `panel`, `image`, `app`, `contract`, and `guards`. Guards cover locale parity, Hebrew only in the Hebrew locale files, Unicode dashes in prose, `build:` in Compose files, tracked secrets and machine-local files, the root file inventory, LF line endings, executable modes, shellcheck, and shfmt. The text guard is `scripts/check-text.py` (stdlib only); it reads the tracked file list from `git ls-files` on the host, so its container needs no Git.
- **CI shape.** `ci.yml` runs on pull requests (changed areas only, guards always), weekly, and manually (all areas plus dependency audits with pip-audit and npm audit). It asks `scripts/verify.sh --changed --print-areas` which areas a change touches, so the path mapping lives in one place; a matrix calls the reusable `verify-area.yml` per area, and `windows-build.yml` builds the Windows client with `scripts/windows.ps1` when the app changes. `summary` is the single required check. Superseded pull request runs are cancelled; scheduled and manual runs never are. Actions are pinned by commit SHA (verified against their tags on 2026-09-30).
- **Publish shape.** A `vX.Y.Z` tag that matches `VERSION` runs the full verification, pushes `ghcr.io/tildeck/tildeck-server:X.Y.Z` with provenance and an SBOM, builds the signed APK (release key from the `release` environment) and the zipped Windows client, then creates a draft GitHub Release from the version's CHANGELOG section, attaches both files, and publishes it. An already published release stops the run.
- **Lockfiles.** Every install fails on a lockfile that no longer matches its manifest: `uv sync --locked` in `server/Dockerfile` (`--frozen` would not check), `npm ci`, and `flutter pub get --enforce-lockfile`. The uv cooldown is stored in `uv.lock` as a span (`P7D`), so `--locked` does not expire with time.
- **CI runners.** The repository is public, so CI uses GitHub-hosted runners (`ubuntu-latest`, and `windows-latest` for the Windows client).
- **Line endings.** The repository-local `core.autocrlf` is `false` and `core.eol` is `lf` (with `* text=auto`, the default native `core.eol` would still check files out as CRLF on Windows), so files on disk stay LF for Linux containers. `.gitattributes` forces CRLF only for `*.ps1`.

## Known unknowns and blockers

| Question or blocker | Why it matters | Evidence or decision needed | Owner |
|---|---|---|---|
| Public release of the repository | Branch rules, secret scanning, and private vulnerability reporting need a public repository on the free plan | Shlomi decides when; then enable those three and require the `summary` check on `main` | Shlomi |
| Windows package format | Release artifacts and install experience | Zip, MSIX, or installer; unsigned in every case. The publish workflow ships a zip until this is decided | Shlomi, before the first release |
| Android release signing | A release APK must be signed with a stable key forever | Create the keystore and keep its backup outside the repository; store it in the `release` environment secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. The publish workflow fails clearly without them | Shlomi, before the first release |
| `xterm` maintenance | The terminal is the core of the client | The risk materialized on 2026-09-30: typing did nothing on Windows, a known xterm 4.0.0 bug with Flutter 3.44 whose fixes upstream never merged. The app now uses a patched copy in `app/third_party/xterm` (see its `PATCHES.md`). Return to the published package when upstream releases the fix, or keep maintaining the copy | Ongoing |

## Ready-for-implementation criteria

- Shlomi approves this plan.
- Local `git init` and local commits are approved as part of starting the foundation task.
- Any GitHub action (repository creation, settings, first push) is authorized separately.

## Handoff to foundation implementation

**First task:** implement deliverables 1 through 13 in order, locally.

**Permitted scope:** repository baseline, toolchain containers, the minimal server, API contract, panel, and client shells described above, Docker definitions, the workflow scripts, CI workflows, and Dependabot configuration. Update `README.md`, `AGENTS.md`, and this document as items become real, with their verification evidence.

**Out of scope:** any product feature (vault, SSH, terminal, accounts, email, sync API, panel screens beyond the shell, SFTP), the cryptography implementation, GitHub organization or repository creation, pushing, and releasing.

**Stopping point:** `scripts/verify.sh` passes a full run in WSL; `scripts/local.sh up` brings both containers to healthy with non-root runtime identities and serves the panel shell; `scripts/windows.ps1` launches the client shell; the panel and Android screenshots are inspected; CI workflows are written and validated locally where possible. Then stop and report before deliverable 14, which needs Shlomi's authorization.
