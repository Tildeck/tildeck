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
| Cryptography design | Proposed in [docs/security-model.md](security-model.md), awaiting Shlomi's review | Argon2id from the master password; separate derived key-encryption key and authentication key; a random vault key wrapped by the password and by the recovery key; per-record XChaCha20-Poly1305 via libsodium | Established primitives with an audited library. Vault and sync code merge only after the document is approved. |
| Admin panel sign-in | Approved (2026-09-30) | Separate administrator accounts with a password and mandatory TOTP, the first one created in first-run setup with a one-time setup token from the server log | The panel manages the server, not vaults, so it does not need vault keys. Pay's Entra sign-in does not fit a public self-hosted product. |
| Release artifacts | Provisional | Android APK, Windows package, server image in GHCR, all from one tagged release | Windows package format (zip, MSIX, or installer) is deferred. |
| Versioning | Provisional | One SemVer version for the whole product; single source of truth is a root `VERSION` file, as in Pay; the release workflow writes it into `app/pubspec.yaml`, and the server image and panel receive it at build time | Client, server, and panel ship together and share a contract. Three ecosystems need one neutral source. |
| Development database storage | Approved | Named volume in development, bind mount in production | PostgreSQL's `initdb` cannot set the permissions it needs on a bind mount of a Windows drive, and the repository lives on `C:`. Pay and hub use the same exception. |
| TLS termination | Approved | The operator's own TLS reverse proxy; Tildeck does not bundle one. Development and phone testing go through Shlomi's existing HTTPS proxy | Shlomi has a proxy ready (2026-09-30). |
| Client cryptography library | Provisional | `sodium` 4.0.4 (libsodium, bundled through build hooks) | The last release that supports Dart 3.12 in the pinned Flutter 3.44; 4.1 needs Dart 3.13. `sodium_libs` is discontinued, and `flutter_sodium` is unmaintained. |
| Product scope of the working version | Approved (2026-09-30) | The full first-release scope, built in the order of the product implementation plan | Shlomi: the proof of concept is a product that works. |
| Brand colors and mark | Provisional | Deep teal ink desk band with a bright teal accent; the mark is a tilde stroke on a rounded tile (`panel/public/favicon.svg`, `panel/app/components/AppLogo.vue`) | Proposed during the panel shell; awaiting Shlomi's review of the screenshots. No purple. |

## Publication and language policy

Tildeck is public-ready. Repository documentation, `AGENTS.md`, code, comments, identifiers, fixtures, tests, commit messages, Issues, pull requests, and review discussion are in English.

Hebrew text is allowed only in these locale files, whose exact paths are finalized when they are created:

- `app/lib/l10n/app_he.arb` (client)
- `panel/i18n/locales/he.json` (admin panel)
- The Hebrew locale file for server email templates under `server/`

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

**Settings known so far:** SMTP host, port, security mode, username, password, and sender address; public server URL; registration mode (for example closed, invite-only, or open); session and token lifetimes; and sign-in rate limits. The final list is set in the sync and panel phases.

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
| 1 | Security model | Proposed, awaiting approval | `docs/security-model.md` defines keys, wrapping, records, accounts, devices, recovery, sync, and the admin panel's boundaries | Shlomi approves it |
| 2 | SSH sessions and terminal | Done in code and tests; waiting for Shlomi's try on his phone and on Windows | Connect with password or private key; sessions in tabs; host key verification with a clear changed-key warning; terminal always LTR; Android key bar (Esc, Tab, Ctrl, arrows); copy and paste | Tests against a pinned OpenSSH container; APK and Windows build tried by Shlomi |
| 3 | Local vault and hosts | Planned; needs step 1 approved | Master password; hosts in groups; private keys and known host keys stored as encrypted records; auto-lock | Tests that no plaintext reaches storage; APK and Windows build |
| 4 | Accounts and email | Planned; needs step 1 approved | Registration by mode, email verification, pre-login, sign-in, new-device approval, recovery, security emails, rate limits, stable error codes | Server tests against PostgreSQL and an SMTP stub |
| 5 | End-to-end sync | Planned; needs steps 3 and 4 | Pull and push with versions, conflicts, and tombstones; protocol check | Two clients converge in tests; Shlomi syncs his phone and Windows through his HTTPS proxy |
| 6 | Admin panel screens | Planned | First-run setup with a one-time token, administrator TOTP, users, devices, settings with environment locks, activity log | Panel screenshots in both languages and themes |
| 7 | SFTP | Planned | Browse, upload, and download over an open session | Tests against the OpenSSH container |

### Step 2 notes (2026-09-30)

- The client opens SSH sessions in tabs (`dartssh2` 4.1.0, `xterm` 4.0.0) with password or private key authentication (Ed25519, ECDSA, RSA; passphrase-protected keys). Credentials stay in memory for the session only; saved hosts and keys come with the vault (step 3).
- Host keys: the first connection shows the SHA-256 fingerprint and asks; a trusted key connects silently; a changed key blocks with a warning, where cancel is the default and replacing the key is a deliberate action. Trusted keys live in `known_hosts.json` in the app support directory until the vault takes them over as records.
- The terminal is always LTR, uses the bundled JetBrains Mono (SIL Open Font License), copies and pastes with Ctrl+Shift+C and Ctrl+Shift+V or a right click on desktop, and on Android shows a key bar (Esc, Tab, Ctrl latch, arrows, common symbols, copy, paste).
- Verification: `scripts/verify.sh --area app` starts a throwaway OpenSSH server (`openssh` in `scripts/toolchain/Dockerfile`), generates a password and two Ed25519 keys for the run, and runs integration tests against it: password and key sign-in, a wrong password, a key that needs its passphrase and a wrong passphrase, a changed host key refused, a closed port, and an interactive shell through the terminal. The same tests pass natively on Windows against the same server. Golden images cover the connect form (both languages and themes), the terminal with the key bar, the changed host key warning, and the sync server page.
- Found and fixed while testing: a refused changed host key was reported as an authentication failure, because the library surfaces the closed transport as an authentication abort.
- Found by Shlomi on Windows: the terminal connected but accepted no typing. xterm 4.0.0 opens its keyboard connection without a view id, which Flutter's Windows embedder rejects since 3.44 (upstream pull requests #224, #228, #231, none merged). Fixed in the vendored copy; `app/test/terminal_input_test.dart` fails without the fix. The test binding accepts the call either way, which is why the earlier end-to-end typing test could not catch it.

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
| Security model approval | Gates the vault and sync code | Shlomi reads and approves `docs/security-model.md` | Shlomi |

## Ready-for-implementation criteria

- Shlomi approves this plan.
- Local `git init` and local commits are approved as part of starting the foundation task.
- Any GitHub action (repository creation, settings, first push) is authorized separately.

## Handoff to foundation implementation

**First task:** implement deliverables 1 through 13 in order, locally.

**Permitted scope:** repository baseline, toolchain containers, the minimal server, API contract, panel, and client shells described above, Docker definitions, the workflow scripts, CI workflows, and Dependabot configuration. Update `README.md`, `AGENTS.md`, and this document as items become real, with their verification evidence.

**Out of scope:** any product feature (vault, SSH, terminal, accounts, email, sync API, panel screens beyond the shell, SFTP), the cryptography implementation, GitHub organization or repository creation, pushing, and releasing.

**Stopping point:** `scripts/verify.sh` passes a full run in WSL; `scripts/local.sh up` brings both containers to healthy with non-root runtime identities and serves the panel shell; `scripts/windows.ps1` launches the client shell; the panel and Android screenshots are inspected; CI workflows are written and validated locally where possible. Then stop and report before deliverable 14, which needs Shlomi's authorization.
