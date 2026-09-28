# AGENTS.md

## Project

Tildeck is a free, open source SSH client for Windows and Android (Flutter) with end-to-end encrypted sync through a self-hosted server (Python FastAPI, PostgreSQL, Docker Compose) and a web admin panel for operators (Nuxt, served by the server).

**Stage: foundation implementation.** What exists today: the repository baseline; the server shell in `server/` (FastAPI, settings registry, activity log, Alembic, health endpoints, `server/openapi.json`, one `server/Dockerfile` that also builds the panel); the admin panel shell in `panel/`; `docker-compose.yml`, `.env.example`, and the development Compose template; and `scripts/local.sh`. The client, the other workflow scripts, and CI do not exist yet.

[docs/project-foundation.md](docs/project-foundation.md) is the desired state, not the current state. Do not assume that any file, directory, command, or script it describes exists. Check its status column and verify before relying on anything. Update the plan and this file as items become real.

## Repository policies

- Public-ready: all repository text, code, comments, identifiers, tests, commits, Issues, and pull requests are in English. Hebrew is allowed only in the locale files listed in the foundation plan. Tests load Hebrew samples from those files.
- Keep the repository root minimal. Every root file must be listed and justified in the foundation plan.
- Workflow scripts live under `scripts/`: WSL Bash `local.sh`, `verify.sh`, `try-pr.sh`, `release.sh`, and `windows.ps1` for the Windows desktop client only. Do not add other alternate-shell scripts.
- Commit lockfiles and install from them.
- Record user-visible and operational changes under `Unreleased` in `CHANGELOG.md`. Do not bump the version in pull requests; the release workflow does that.
- Never commit secrets, `.env`, `docker-compose-dev.yml`, or signing keys.
- Pay (the `MosesGroups/payments` repository) is the design reference for the admin panel. Its code may be reused here under Apache-2.0 (confirmed by Shlomi); adapt it to Tildeck and leave out Pay-specific parts (Cardcom, CRM, Entra).

## Architecture rules

- Plaintext user secrets exist only in the client. The server stores and returns opaque ciphertext and metadata. Neither the server nor the admin panel may need or expose plaintext vault data.
- Never log passwords, private keys, vault contents, tokens, or secret settings, in any component.
- Cryptography uses established primitives through libsodium, as defined in `docs/security-model.md` once approved. Do not invent cryptographic constructions.
- There is no password reset. Recovery works only through the user's recovery key.
- Settings: every operator setting is declared once in the server's settings registry and is editable in the admin panel. A set environment variable wins and locks the field; the admin API refuses writes to locked settings. Stored values are encrypted at rest and every change is written to the activity log. Sensitive values (passwords, keys, tokens, credentials) are never returned by any API or displayed in the panel, not even read-only or when set by the environment; the panel shows only their state. Only bootstrap values (database connection, settings encryption key) are environment-only.
- User-facing strings, including email content, go through the localization system in English and Hebrew from the start. UIs support RTL and LTR and light and dark themes. Terminal content is always LTR.
- The server returns stable error codes. Clients map them to localized messages.
- The server's committed OpenAPI document is the client and server contract. The app's Dart API client is generated from it; never edit generated code by hand. Change the server, re-export the document, regenerate the client, and commit all three together.

## Known traps

- Run Docker from WSL in a login shell (`bash -l`). Otherwise the Docker Desktop credential helper is not on `PATH` and pulls fail with "error getting credentials".
- The repository path contains a space (`/mnt/c/Users/Shlomi Porush/...`). Quote every path in scripts.
- `server/Dockerfile` builds the panel from a named build context: `docker build --build-context panel=./panel -f server/Dockerfile ./server`.
- `docker-compose-dev.yml` is machine-local. Create it once with `cp docs/development/docker-compose-dev.example.yml docker-compose-dev.yml`, and `.env` with `cp .env.example .env`.
- PostgreSQL 18 images keep data under `/var/lib/postgresql`, not `/var/lib/postgresql/data`.
- A container's runtime UID is the UID of its PID 1. `docker exec ... id -u` reports the exec session's user instead.

- Flutter cannot build the Windows desktop app from WSL or Linux. Use `scripts/windows.ps1` locally; CI builds it on a Windows runner.
- Android blocks cleartext HTTP by default, so sync deployments need HTTPS.
- The Android application ID `com.tildeck.app` cannot change after the first public release.
- The repository lives on a Windows drive. PostgreSQL cannot initialize on a bind mount of a Windows drive, so development uses a named volume (approved exception).

## Docker

Docker runs the sync server (which also serves the admin panel) and PostgreSQL. The development stack is `scripts/local.sh` on `http://localhost:8280`.

- `docker-compose.yml` (tracked) is the production file and references published GHCR images. `docker-compose-dev.yml` (root, ignored, never committed) is the machine-local development file and references explicit `:dev` images such as `tildeck-server:dev`. Use it only through `scripts/local.sh`. If it is missing, `local.sh` must fail with a clear message and never fall back to the production file.
- Neither Compose file may contain `build:`. Scripts build images explicitly. A CI guard enforces this.
- Container runtime variables come from `.env` through `env_file`. `.env.example` is the tracked contract with placeholder values only. Keep Compose interpolation to values Compose itself needs (image tag, host data directory).
- Every application container runs as a dedicated non-root user. Verification fails if an application process runs as UID 0.
- Every long-running container has a real health check: the server image's health check command calls the readiness endpoint, which checks including the database; PostgreSQL uses `pg_isready`.
- Production PostgreSQL data lives in a bind-mounted host directory writable by the container's `postgres` UID. Back up with `pg_dump`. Ordinary `down` keeps the data; only the confirmed `nuke` operation removes it.
- Logs go to stdout and stderr.
