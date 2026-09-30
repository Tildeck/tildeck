# Changelog

All notable changes to Tildeck are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- The admin panel: first-run setup with a one-time token, administrator sign-in with a password and an authenticator code, users and their devices, settings with values locked by the environment, and the activity log, in English and Hebrew.
- End-to-end encrypted sync: create a sync account from the client with a one-time recovery key, sign in on another device and approve it from a signed-in one or by email, and keep hosts, keys, and trusted host keys in step, with conflicts going to the newer edit.
- Accounts on the sync server: registration with email verification, sign-in per device, approval of new devices, device revocation, master password change, recovery with the recovery key, and security emails in English and Hebrew.
- A local encrypted vault in the client: a master password, saved hosts in groups, private keys, and trusted host keys, all encrypted on the device; automatic lock after 15 minutes.
- SSH sessions in the client: connect with a password or a private key, sessions in tabs, host key verification with a warning when a server's key changes, and an on-screen key bar on Android.
- Project foundation: repository baseline, sync server shell with health checks and a settings registry, admin panel shell, client app shell for Windows and Android, Docker definitions, workflow scripts, and CI.
