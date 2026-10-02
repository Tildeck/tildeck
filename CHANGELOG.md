# Changelog

All notable changes to Tildeck are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- On the desktop, hosts as a grid of cards with a right-click menu, edited in a side panel beside them.
- A desktop layout for wide windows: a sidebar with every section, each opening in place, and the session tabs above.
- Known hosts: see the trusted server keys with their fingerprints, and stop trusting one.
- Files: cancel a transfer, download and upload whole folders on the desktop, and select several entries to download or delete together.
- Edit text files on the server, with a warning when the file changed there since it was opened.
- Files: rename, permissions, copy the path, and delete (folders with their contents, after asking); hidden files and sorting; go to a path; and a host's files opened directly from its menu, without a terminal.
- SSH certificates: a key can carry an OpenSSH user certificate, offered first when it signs in, with who it is for and until when shown on the Keys page.
- Keys: generate Ed25519 or RSA 4096 keys, import from a file, see fingerprints, copy the public key, install it on a server, and export the private key protected by a passphrase.
- A local terminal on the desktop: PowerShell, Command Prompt, or WSL on Windows, in a tab like a session.
- Telnet hosts, for devices that have nothing else, through jump hosts and proxies like SSH, with a warning that Telnet is not encrypted.
- Proxies: reach hosts through a SOCKS5 or HTTP proxy, with a password if it asks for one, chosen per host or per group.
- Agent forwarding per host: the server can sign in onward with the vault's keys during the session, without the keys leaving the device.
- Jump hosts: connect to a host through another saved host, or a chain of them, set per host or per group.
- Port forwarding: local, remote, and dynamic (SOCKS5) rules through saved hosts, synced across devices, turned on and off from their own page.
- Split view on wide screens: two sessions side by side.
- Autocomplete from the server's own history and from snippets, and the saved password offered at a password prompt; nothing typed is stored.
- Connection history across devices, with recent hosts for one-tap reconnecting.
- Terminal color schemes and font size, kept in step across devices; search in the terminal; renaming a tab.
- Host tags and search, group settings that hosts inherit (username, key, startup snippet, environment variables), and environment variables per host.
- Snippets: saved commands to run in a session, on several hosts at once, or when a host's session starts.
- Files over SFTP in an open session: browse folders, download, upload, and create a folder.
- Change the master password in the client, and recover a forgotten one with the recovery key.
- Invitations: an administrator invites an email address from the admin panel, and registering with the code confirms the address, with or without email configured.
- The admin panel: first-run setup with a one-time token, administrator sign-in with a password and an authenticator code, users and their devices, settings with values locked by the environment, and the activity log, in English and Hebrew.
- End-to-end encrypted sync: create a sync account from the client with a one-time recovery key, sign in on another device and approve it from a signed-in one or by email, and keep hosts, keys, and trusted host keys in step, with conflicts going to the newer edit.
- Accounts on the sync server: registration with email verification, sign-in per device, approval of new devices, device revocation, master password change, recovery with the recovery key, and security emails in English and Hebrew.
- A local encrypted vault in the client: a master password, saved hosts in groups, private keys, and trusted host keys, all encrypted on the device; automatic lock after 15 minutes.
- SSH sessions in the client: connect with a password or a private key, sessions in tabs, host key verification with a warning when a server's key changes, and an on-screen key bar on Android.
- Project foundation: repository baseline, sync server shell with health checks and a settings registry, admin panel shell, client app shell for Windows and Android, Docker definitions, workflow scripts, and CI.

### Fixed

- A host's environment variable that the server does not accept no longer fails the session; it is skipped, as ssh does.
