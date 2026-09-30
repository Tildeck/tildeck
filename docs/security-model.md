# Tildeck Security Model

Status: Proposed, 2026-09-30. Vault and sync code may be merged only after Shlomi approves this document; the approval is recorded in `docs/project-foundation.md`.

This document defines how Tildeck protects users' SSH hosts, keys, and credentials: what is encrypted, with which keys, where each key lives, what the sync server and its operator can and cannot learn, and how accounts, devices, recovery, and sync work. It uses only established primitives through an audited library. Nothing here is a new cryptographic construction.

## Goals and non-goals

**Goals.**

- Plaintext vault contents (hosts, usernames, passwords, private keys, known host keys, settings) exist only on the user's devices.
- The sync server and its operator cannot read or modify vault contents without detection.
- A stolen database dump is only as weak as the user's master password, and the password is expensive to guess.
- Every device can be revoked on its own.
- Losing the master password without the recovery key loses the synced data. There is no password reset.

**Non-goals.**

- Hiding metadata from the server: it sees the account email, the number, size, and timing of records, and device names and last-seen times.
- Protecting a device that is already compromised while the vault is unlocked.
- Protecting against a malicious client build. Clients are installed from the project's GitHub Releases.

## Primitives and libraries

| Purpose | Primitive | Implementation |
|---|---|---|
| Password stretching | Argon2id (`crypto_pwhash`, Argon2id 1.3) | libsodium |
| Subkey derivation | BLAKE2b keyed KDF (`crypto_kdf_derive_from_key`) | libsodium |
| Record and key encryption | XChaCha20-Poly1305 IETF AEAD (`crypto_aead_xchacha20poly1305_ietf`), random 24-byte nonces | libsodium |
| Random bytes | `randombytes_buf` | libsodium |
| Hashing for integrity checks | BLAKE2b (`crypto_generichash`) | libsodium |
| Server-side password hashing | Argon2id | `argon2-cffi` (Python) |
| Token storage on the server | SHA-256 of a 256-bit random token | Python standard library |
| Administrator second factor | TOTP (RFC 6238: SHA-1, 30 seconds, 6 digits) | `pyotp` |
| Transport | TLS, terminated by the operator's reverse proxy | Operator infrastructure |

The client uses libsodium through the Dart package `sodium` (4.0.4, the last release that supports Dart 3.12 in the pinned Flutter 3.44; it bundles libsodium for Windows and Android through build hooks). The package is pinned and updated through the lockfile like any other dependency.

## Keys

All keys are 32 bytes unless stated otherwise.

| Key | Created | Derived from or protected by | Where it lives | Sent to the server |
|---|---|---|---|---|
| Master password | By the user | | The user's memory | Never |
| Password key `PK` | At every unlock | Argon2id(master password, salt, params) | Memory, only during unlock | Never |
| Authentication key `AK` | At every unlock | `crypto_kdf(PK, id 1, context "tdauth01")` | Memory, only during sign-in | Yes, over TLS; the server stores only an Argon2id hash of it |
| Key-encryption key `KEK` | At every unlock | `crypto_kdf(PK, id 2, context "tdwrap01")` | Memory, only during unlock | Never |
| Vault key `VK` | Once, at vault creation | Random | Memory while the vault is unlocked; stored only wrapped | Only wrapped |
| Recovery key `RK` | Once, at registration | Random | Written down by the user | Never; the server stores a hash of its authentication key |
| Recovery authentication key `RAK` | When the recovery key is used | `crypto_kdf(RK, id 1, context "tdrecv01")` | Memory, only during recovery | Yes, over TLS; stored as an Argon2id hash |
| Recovery wrapping key `RWK` | When the recovery key is used | `crypto_kdf(RK, id 2, context "tdrecv01")` | Memory, only during recovery | Never |
| Device token | At each sign-in | Random | The device's secure storage | Yes, on each request; the server stores its SHA-256 |

**Wrapped vault key.** The vault key is stored twice, each copy encrypted with XChaCha20-Poly1305 under a random nonce:

- `wrap_pw = AEAD(KEK, VK, ad = "tildeck:wrap:password:v1|" + account_id)`
- `wrap_rk = AEAD(RWK, VK, ad = "tildeck:wrap:recovery:v1|" + account_id)`

Changing the master password re-wraps the same vault key; records are never re-encrypted for a password change.

**Argon2id parameters.** Operations limit 3, memory limit 64 MiB (libsodium's parallelism is fixed at 1), a 16-byte random salt per account. These fit the slower supported phones while making each guess cost about a third of a second on a desktop. The parameters are stored with the account, so they can be raised later: the next unlock with the old parameters re-derives the keys with the new ones and re-wraps the vault key.

**Master password rules.** At least 12 characters; the client refuses passwords found in a small built-in list of the most common passwords. The client explains, once, that there is no password reset and that the recovery key is the only way back.

**Recovery key format.** 32 random bytes plus a 2-byte BLAKE2b checksum, written as Crockford Base32 in groups of four characters. The checksum catches typing mistakes before any network request.

## The vault on a device

- Records are stored locally in the same encrypted form they are synced in (below). The local database never holds plaintext record contents.
- Unlocking the vault: the master password derives `PK`, then `KEK`, which unwraps `VK` from the locally stored `wrap_pw`. A wrong password fails the AEAD check; nothing else reveals whether a password is right.
- `VK` lives in memory only while the vault is unlocked. The vault locks after an idle period (default 15 minutes, a user setting) and when the app is closed. Buffers holding keys are zeroed when freed where the language allows it.
- The device token is stored in the platform's secure storage (Android Keystore through EncryptedSharedPreferences; Windows DPAPI).
- A device can also use Tildeck without any account: the vault is then local only, with a locally generated salt and no recovery key. Signing in later uploads it.
- Biometric unlock is out of scope for the first release.

## Records

Everything the user stores is a record: a host, a group, a private key, a known host key, or a synced setting. A record is:

| Field | Visible to the server | Notes |
|---|---|---|
| `id` | Yes | UUID v4, generated by the client |
| `version` | Yes | Per record, set by the client: 1 for a new record, then the version it was based on plus 1; the server enforces it |
| `revision` | Yes | Assigned by the server from a counter per account; only the cursor for pulling changes |
| `deleted` | Yes | A tombstone: the record was deleted; `ciphertext` is empty |
| `nonce` | Yes | 24 random bytes, new for every encryption |
| `ciphertext` | Yes, opaque | `AEAD(VK, plaintext, ad)` |
| `updated_at`, `device_id` | Yes | Set by the server |

The plaintext is a versioned JSON document: `{"v": 1, "type": "host", "modified_at": "...", "data": {...}}`. The record type is inside the ciphertext, so the server does not learn which records are hosts and which are keys.

The associated data binds a ciphertext to its place: `ad = "tildeck:record:v1|" + account_id + "|" + id + "|" + version`. The client knows the version when it encrypts, because it sets it. A server that moves a ciphertext to another record or another account, or replays an old ciphertext under a newer version number, fails the AEAD check on the client. The client remembers the highest version it has seen for each record and refuses an older one, so a server that silently rolls a record back is detected. A server can still withhold records or refuse service; that is a denial of service, not a disclosure.

## Accounts and devices (server)

**Registration.** The client generates the salt, derives `AK`, generates `VK` and `RK`, and sends the email address, the salt and parameters, `AK`, `wrap_pw`, `wrap_rk`, and `RAK`. The server stores Argon2id hashes of `AK` and `RAK` (never the keys), the wraps, and the salt. The client shows the recovery key and requires the user to confirm it before continuing. Whether registration is allowed follows the registration mode setting (closed, invite, open); open registration requires SMTP.

**Email verification.** With SMTP configured, the account stays unverified, and cannot sync, until the link in the verification email is used. Without SMTP, only an administrator can create accounts, and they are verified at creation.

**Pre-login.** Sign-in starts with the email address; the server answers with the salt and parameters. For an unknown address it answers with a deterministic fake salt (a keyed hash of the address with a server secret), so the endpoint does not reveal which addresses have accounts.

**Sign-in.** The client sends `AK` and a device name. The server verifies it against the stored hash and, for a known device, issues a device token. Sign-in attempts are rate-limited per account and per client address, and failures are recorded in the activity log.

**New-device approval.** A sign-in from a device the account has not used before creates a pending device. It receives the wrapped vault key and records only after approval, given from an already signed-in device or, with SMTP, through a link in an email to the account address. Approval is defense in depth for a leaked master password: an attacker with the password still needs one of the user's devices or mailbox.

**Device tokens.** Each device holds its own random 256-bit token; the server stores its SHA-256 and the last-seen time. Tokens expire after a period without use (a setting; default 90 days). Revoking a device deletes its token immediately. Changing the master password revokes every other device unless the user chooses otherwise.

**Recovery.** With the recovery key, the client derives `RAK` and `RWK`, proves `RAK` to the server, downloads `wrap_rk`, unwraps `VK`, and sets a new master password: a new salt, new `AK`, and a new `wrap_pw`. Every other device is revoked, a security email is sent, and the event is logged. The recovery key stays valid; the user can issue a new one at any time, which replaces `wrap_rk` and the `RAK` hash.

**Security notifications.** With SMTP configured, the account address is emailed when a device is added or revoked, the master password changes, or the recovery key is used. Emails are localized in English and Hebrew by the user's language and never contain secrets or links that sign the user in.

## Sync

- Every request carries the header `Tildeck-Protocol: <version>`. A server that does not support it answers with the stable error code `unsupported_protocol`, and the client shows a localized message. The version changes only when an older client could no longer sync correctly.
- **Pull.** `GET /api/sync/records?since=<revision>` returns every record, tombstones included, with a revision above the cursor, in revision order.
- **Push.** The client sends changes, each encrypted with its new `version`. The server accepts a change only if that version is exactly the record's current version plus 1 (1 for a new record), then assigns it the next account `revision` and stores it. A stale change is rejected for that record with the stable error code `version_conflict` and the current record.
- **Conflicts.** For a rejected change, the client decrypts the server's record and compares the `modified_at` times inside the two plaintexts: the newer edit wins. If the local edit wins, the client encrypts it again with the server's version plus 1 and pushes it; otherwise the local change is dropped. A deletion is a change like any other and is kept as a tombstone, so it reaches every device.
- The client pulls before it pushes, and after every sign-in, unlock, and reconnect.

## The admin panel

- Administrator accounts are separate from user accounts and cannot hold a vault. They sign in with a password (Argon2id on the server) and a mandatory TOTP code (RFC 6238). TOTP secrets are stored encrypted with the settings encryption key.
- **First-run setup.** A fresh server prints a one-time setup token to its log and accepts the first administrator only with that token, so nobody can claim an exposed fresh server before the operator does.
- Sessions use an `HttpOnly`, `Secure`, `SameSite=Strict` cookie, expire after inactivity, and state-changing requests require a CSRF token.
- Administrators can create, disable, and delete user accounts, revoke devices, and see metadata (email, created, last seen, device names, record counts, storage used). No API returns ciphertext, wrapped keys, or hashes to the panel, and nothing in the panel can decrypt anything.
- Every administrative action is written to the activity log.

## What a compromised server reveals

An attacker with the full database and the settings encryption key gets email addresses, device names and timestamps, record counts and sizes, Argon2id hashes of `AK` and `RAK`, and the wrapped vault keys. To read a vault they must guess the master password (each guess costs one Argon2id derivation with the account's parameters) or the recovery key (256 bits, infeasible). They cannot sign in as a user without `AK`, and cannot forge or reorder records without detection.

An attacker who controls the running server can additionally withhold or delay records and see which account syncs when, and could serve a new user a fake pre-login salt. They still never receive the master password or `PK`.

## SSH connections

- Host keys are verified on every connection. The first connection to a host shows its fingerprint (SHA-256) and asks the user to trust it; the trusted key is stored as a record and syncs to every device. A changed host key blocks the connection with a clear warning; the user must explicitly replace the stored key.
- Private keys are stored as records in the vault, never as files outside it. Passphrase-protected keys are decrypted in memory only for the connection.
- Passwords typed for a single connection are not stored unless the user asks.
- Supported key types follow `dartssh2` 4.1: Ed25519, ECDSA (P-256, P-384, P-521), and RSA with SHA-2 signatures.

## Logging

No component logs passwords, keys, tokens, record contents, wrapped keys, or secret settings. Logs may contain account and device identifiers, email addresses for security events, and error codes.

## Open for later

- Biometric unlock and hardware-backed keys.
- Sharing records between accounts (teams).
- Raising the Argon2id parameters as hardware improves.
- An independent security review before the project is promoted beyond early adopters.
