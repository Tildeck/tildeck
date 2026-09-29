# Contributing to Tildeck

Thank you for your interest. Tildeck is in its foundation stage, so the codebase is small and moving quickly; please open an issue to discuss a change before starting on anything large.

## What you need

- Windows with WSL 2, or Linux, with Docker. Every build, lint, and test runs in pinned containers, so nothing else is required.
- For the Windows desktop client only: Flutter on Windows and Visual Studio Build Tools with the "Desktop development with C++" workload.

## Everyday commands

Run these from the repository root, in WSL:

- `scripts/local.sh up -b -d` builds and starts the sync server (with the admin panel) and PostgreSQL at http://localhost:8280. The first time, create the machine-local files: `cp .env.example .env` and `cp docs/development/docker-compose-dev.example.yml docker-compose-dev.yml`.
- `scripts/local.sh apk` builds a debug Android APK into `out/`.
- `scripts/local.sh contract` re-exports the server's OpenAPI document and regenerates the Dart API client after a server API change.
- `scripts/verify.sh --changed` verifies what you changed; `scripts/verify.sh` verifies everything. CI runs the same script.

On Windows, `scripts\windows.ps1` runs or builds the desktop client.

## Conventions

- Everything in the repository is in English. Hebrew appears only in the Hebrew locale files.
- User-facing text goes through the localization files in English and Hebrew, and the interfaces support right-to-left and left-to-right layouts and light and dark themes.
- Commit the lockfiles you change. Never commit secrets, `.env`, or `docker-compose-dev.yml`.
- Record user-visible and operational changes under `Unreleased` in `CHANGELOG.md`. Do not change `VERSION`; releases do that.
- Never edit generated code by hand (`app/packages/tildeck_api`, generated localizations).

## License

By contributing, you agree that your contributions are licensed under the Apache License 2.0.
