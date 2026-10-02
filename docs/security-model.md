# Tildeck Security Model

Status: Approved by Shlomi on 2026-09-30. The designs for biometric unlock and two-factor sign-in for user accounts were added and approved by him on 2026-10-02. A change to this document needs his approval again before code that depends on it merges.

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
| Administrator and user account second factor | TOTP (RFC 6238: SHA-1, 30 seconds, 6 digits) | `pyotp` |
| Biometric key protection on Android | AES-256-GCM key in the Android Keystore, released by `BiometricPrompt` | Android platform |
| Biometric key source on Windows | Windows Hello key signature (RSA 2048, PKCS#1 v1.5 with SHA-256) through `KeyCredentialManager` | Windows platform |
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
| Device token | At each sign-in | Random | The local vault file, sealed under `VK` | Yes, on each request; the server stores its SHA-256 |
| Biometric key `BK` | When biometric unlock is turned on, per device | Android: random, encrypted by a Keystore key that needs a strong biometric. Windows: derived from a Windows Hello signature (below) | Never on disk in the clear; in memory only during a biometric unlock | Never |

**Wrapped vault key.** The vault key is stored twice, each copy encrypted with XChaCha20-Poly1305 under a random nonce, and a third time on a device with biometric unlock turned on:

- `wrap_pw = AEAD(KEK, VK, ad = "tildeck:wrap:password:v1|" + vault_id)`
- `wrap_rk = AEAD(RWK, VK, ad = "tildeck:wrap:recovery:v1|" + vault_id)`
- `wrap_bio = AEAD(BK, VK, ad = "tildeck:wrap:biometric:v1|" + vault_id)`, in the local vault file of that device only; it is never synced and never sent to the server.

`vault_id` is a random UUID created on the device together with the vault key. It is not secret: it is sent to the server at registration and stored with the account. Binding to the vault rather than to the account lets a vault created without an account be uploaded later unchanged.

Changing the master password re-wraps the same vault key; records are never re-encrypted for a password change.

**Argon2id parameters.** Operations limit 3, memory limit 64 MiB (libsodium's parallelism is fixed at 1), a 16-byte random salt per account. They are meant to fit the slower supported phones while making each guess expensive; the unlock time on a mid-range phone and on a desktop is measured in product step 3, and the parameters are adjusted if it is unreasonable. The parameters are stored with the account, so they can be raised later: the next unlock with the old parameters re-derives the keys with the new ones and re-wraps the vault key.

**Master password rules.** At least 12 characters; the client refuses passwords found in a small built-in list of the most common passwords. The client explains, once, that there is no password reset and that the recovery key is the only way back.

**Recovery key format.** 32 random bytes plus a 2-byte BLAKE2b checksum, written as Crockford Base32 in groups of four characters. The checksum catches typing mistakes before any network request. The checksum is the first two bytes of the key's 16-byte BLAKE2b hash, libsodium's shortest output; reading a key accepts lower case, spaces, and the letters O, I, and L for 0, 1, and 1. (Clarification recorded on 2026-09-30 while implementing step 5.)

## The vault on a device

- Records are stored locally in the same encrypted form they are synced in (below). The local database never holds plaintext record contents.
- Unlocking the vault: the master password derives `PK`, then `KEK`, which unwraps `VK` from the locally stored `wrap_pw`. A wrong password fails the AEAD check; nothing else reveals whether a password is right. With biometric unlock turned on, `BK` can unwrap `VK` from `wrap_bio` instead (below).
- `VK` lives in memory only while the vault is unlocked. The vault locks after an idle period (default 15 minutes, a user setting) and when the app is closed. Buffers holding keys are zeroed when freed where the language allows it.
- The device token, with the account's email address and server, is stored in the local vault file, sealed under `VK` with XChaCha20-Poly1305 and `ad = "tildeck:local:v1|" + vault_id`. It never syncs. It is therefore readable only while the vault is unlocked, which is the only time a device can sync anyway (records need `VK`), so platform secure storage would add nothing while the vault is locked and a dependency while it is open. (Changed on 2026-09-30 while implementing step 5, from platform secure storage: Android Keystore through EncryptedSharedPreferences, Windows DPAPI. Approved by Shlomi on 2026-10-01.)
- A device can also use Tildeck without any account: the vault is then local only, with a locally generated salt and no recovery key. Registering later uploads the same vault unchanged (records and `wrap_pw` are bound to `vault_id`, not to an account) and creates the recovery key at that point.
- Biometric unlock was out of scope for the first release; Shlomi asked for it on 2026-10-01 (typing the master password at every unlock on a phone is too much). It comes with stage 3 of the Termius parity plan; its design follows. (Approved by Shlomi on 2026-10-02.)

**Biometric unlock.** Optional and per device, off by default, turned on in Settings > Security.

- **Turning it on.** The vault must be unlocked, and the user types the master password once more; it is checked by unwrapping `wrap_pw`. The client then obtains `BK` as below and stores `wrap_bio = AEAD(BK, VK, ad = "tildeck:wrap:biometric:v1|" + vault_id)` in the local vault file. `vault_id` is the same random UUID that binds `wrap_pw`, `wrap_rk`, and the records. Neither `BK` nor `wrap_bio` is synced or sent to the server.
- **Android.** `BK` is 32 random bytes. It is encrypted with AES-256-GCM under a key in the Android Keystore created with `setUserAuthenticationRequired(true)`, `setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)` (a strong biometric for every use, no device credential), `setInvalidatedByBiometricEnrollment(true)`, and StrongBox when the device has it. The encrypted `BK` and its GCM nonce are kept in the local vault file next to `wrap_bio`. Decryption runs through `BiometricPrompt` with a `CryptoObject`, so the system releases the Keystore key only after a strong biometric.
- **Windows.** Windows Hello through `KeyCredentialManager`. A Hello key is created for the vault (named after `vault_id`). To obtain `BK`, the client asks Hello to sign the fixed challenge `"tildeck:biometric:challenge:v1|" + vault_id` with that key; the signature is RSA PKCS#1 v1.5, which is deterministic, so the same key always gives the same signature. Then `H = crypto_generichash(32 bytes, signature)` and `BK = crypto_kdf(H, id 1, context "tdbio001")`. Nothing derived from the signature is stored. Windows Hello accepts the user's Hello PIN as well as a face or fingerprint, and Tildeck cannot restrict that, so on Windows this protection is that of Windows Hello. If a signature ever came out different, the AEAD check would fail and the master password would be asked for.
- **Unlocking with it.** The client obtains `BK`, unwraps `VK` from `wrap_bio`, and opens the vault exactly as a password unlock does; `BK` is then dropped from memory. A failure or a cancel falls back to the master password, which always remains available. The idle lock and the lock when the app closes are unchanged.
- **What removes it.** Turning it off deletes `wrap_bio` and the Android Keystore key or the Windows Hello key. Changing the master password or using the recovery key on the device deletes `wrap_bio` too, and so does a device taking a new `wrap_pw` from the server after the password changed elsewhere. A new biometric enrollment on Android invalidates the Keystore key, and a deleted Hello key leaves nothing to sign with: the client then deletes `wrap_bio`. In every case the user turns it on again with the master password.
- **What it protects.** An attacker with the device's files but without the user's biometric (on Windows, without Windows Hello) cannot unwrap `VK` from `wrap_bio`. It does not protect against an attacker who can pass the operating system's biometric check (or the Windows Hello PIN): that is the same protection as the device's own lock. The server learns nothing; it does not even know whether a device uses biometric unlock.

## Records

Everything the user stores is a record: a host (with its group name), a private key, a known host key, or a synced setting. A record is:

| Field | Visible to the server | Notes |
|---|---|---|
| `id` | Yes | UUID v4, generated by the client; unique within the vault |
| `version` | Yes | Per record, set by the client: 1 for a new record, then the version it was based on plus 1; the server enforces it |
| `revision` | Yes | Assigned by the server from a counter per account; only the cursor for pulling changes |
| `deleted` | Yes | A tombstone: the record was deleted; `ciphertext` is empty, or holds the deletion marker (below) |
| `nonce` | Yes | 24 random bytes, new for every encryption |
| `ciphertext` | Yes, opaque | `AEAD(VK, plaintext, ad)` |
| `updated_at`, `device_id` | Yes | Set by the server |

The plaintext is a versioned JSON document: `{"v": 1, "type": "host", "modified_at": "...", "data": {...}}`. The record type is inside the ciphertext, so the server does not learn which records are hosts and which are keys.

The associated data binds a ciphertext to its place: `ad = "tildeck:record:v1|" + vault_id + "|" + id + "|" + version`. The client knows the version when it encrypts, because it sets it. A server that moves a ciphertext to another record or another vault, or replays an old ciphertext under a newer version number, fails the AEAD check on the client. The client remembers the highest version it has seen for each record and refuses an older one, so a server that silently rolls a record back is detected. A server can still withhold records or refuse service; that is a denial of service, not a disclosure.

## Accounts and devices (server)

**Registration.** The client generates the salt, derives `AK`, generates `VK`, `vault_id`, and `RK`, and sends the email address, `vault_id`, the salt and parameters, `AK`, `wrap_pw`, `wrap_rk`, and `RAK`. The server stores Argon2id hashes of `AK` and `RAK` (never the keys), the wraps, and the salt. The client shows the recovery key and requires the user to confirm it before continuing. Whether registration is allowed follows the registration mode setting (closed, invite, open); open registration requires SMTP. **Invitations** (approved by Shlomi on 2026-10-01): an administrator invites one email address; the invitation code is 96 random bits, stored as its SHA-256, single use, and valid for 7 days. Registering with it is allowed in the invite and open modes, needs no SMTP, and confirms the address, because the administrator vouched for it.

**Email verification.** With SMTP configured, the account stays unverified, and cannot sync, until the link in the verification email is used. Without SMTP, only an administrator can create accounts, and they are verified at creation.

**Pre-login.** Sign-in starts with the email address; the server answers with the salt and parameters. For an unknown address it answers with a deterministic fake salt (a keyed hash of the address with a server secret), so the endpoint does not reveal which addresses have accounts.

**Sign-in.** The client sends `AK` and a device name. The server verifies it against the stored hash and, for a known device, issues a device token. Sign-in attempts are rate-limited per account and per client address, and failures are recorded in the activity log.

**New-device approval.** A sign-in from a device the account has not used before creates a pending device. It receives the wrapped vault key and records only after approval, given from an already signed-in device or, with SMTP, through a link in an email to the account address. Approval is defense in depth for a leaked master password: an attacker with the password still needs one of the user's devices or mailbox.

**Collecting an approval.** A sign-in with a correct `AK` from a device the account does not know creates a pending device and returns its id and a one-time claim token (256 random bits; the server stores its SHA-256). The pending device receives no token, wrapped key, or record. Once the device is approved, the device presents the claim token once and receives its device token, `vault_id`, the KDF parameters, and `wrap_pw`. Knowing the master password is therefore not enough to collect an approval: the claim token exists only on the device that asked. An approval by email uses a separate one-time link token that expires after one hour. An active device whose token expired signs in again with the same device id and `AK` and needs no new approval; a revoked device is a new device. (Clarification recorded on 2026-09-30 while implementing step 4; it does not change the approved decisions.) A device id is not a secret (it appears in the activity log and the admin panel), so a sign-in with an active device's id while that device still holds a working token (issued, and not idle past the limit) gives no token: the device becomes pending again, its token stops working, and it needs a new approval. (Approved by Shlomi on 2026-10-02, from the security review.)

**Device tokens.** Each device holds its own random 256-bit token; the server stores its SHA-256 and the last-seen time. Tokens expire after a period without use (a setting; default 90 days). Revoking a device deletes its token immediately. Changing the master password revokes every other device unless the user chooses otherwise.

**Recovery.** With the recovery key, the client derives `RAK` and `RWK`, proves `RAK` to the server, downloads `wrap_rk`, unwraps `VK`, and sets a new master password: a new salt, new `AK`, and a new `wrap_pw`. Every other device is revoked, a security email is sent, and the event is logged. The recovery key stays valid; the user can issue a new one at any time, which replaces `wrap_rk` and the `RAK` hash.

**Two-factor sign-in.** Optional per account. (Approved by Shlomi on 2026-10-02.)

- **Turning it on.** From Settings > Security in the app, on a signed-in device. The server generates a TOTP secret (RFC 6238: SHA-1, 30 seconds, 6 digits, the same as administrators), stores it encrypted with the settings encryption key (`CONFIG_ENCRYPTION_KEY`) as it does the administrators' secrets, and returns it as an `otpauth://` address and a QR code. It becomes active only after a code from it is confirmed. Turning it off needs a current code.
- **Where a code is required.** While it is active: at sign-in, on any device, new or known; at a master password change; and at recovery, when it starts (before the server returns `wrap_rk`). The request that completes recovery must not be possible with the recovery key alone; how it is tied to a start that passed the code is settled when this is built. Devices that are already signed in stay signed in when two-factor sign-in is turned on.
- **Codes.** A code is accepted once: the time step of each accepted code is stored, and that step and earlier ones are refused, so a code cannot be replayed. One step of clock drift is allowed either way. Wrong codes count against the same per-account and per-address limits as sign-in, and only a complete sign-in gives an attempt back. A wrong password and a wrong code get the same answer (`invalid_credentials`, or `recovery_failed` at recovery). The one difference is a stable error code that tells the client a code is needed: `totp_required`, given when the request carries no code and the password (or the recovery key) is right. It is given only after that check, so it does not reveal which accounts exist or use two-factor sign-in; it does tell someone who already has the password that the password is right, as any two-step sign-in does, and those attempts are limited and logged like any other.
- **A lost authenticator.** An administrator can turn two-factor sign-in off for the account in the admin panel. The action is written to the activity log, and the user receives a security email. There are no backup codes in this version.
- **What it does not change.** The TOTP secret is not part of the vault, and the server can read it. It is a second factor for the account (signing in, changing the password, recovery), not for the vault's encryption: the keys, the wraps, and what a master password or recovery key can decrypt are exactly as above.

**Security notifications.** With SMTP configured, the account address is emailed when a device is added or revoked, the master password changes, the recovery key is used, or two-factor sign-in is turned on or off (by the user or by an administrator). Emails are localized in English and Hebrew by the user's language and never contain secrets or links that sign the user in.

## Sync

- Every request carries the header `Tildeck-Protocol: <version>`. A server that does not support it answers with the stable error code `unsupported_protocol`, and the client shows a localized message. The version changes only when an older client could no longer sync correctly.
- **Authenticated deletions.** A deletion carries a marker: `{"deleted": true}` encrypted like a record's plaintext, under `VK` with the record's own associated data (`vault_id`, record id, version). A device deletes an entry it has only for a tombstone whose marker opens under `VK` and says so; a tombstone without one, or with one that does not open, may come from the server alone, so the entry stays and is reported. A tombstone for a record the device does not have is taken as it is: there is nothing to delete. Tombstones written before this change carry no marker: a device that still has such an entry keeps it. (Approved by Shlomi on 2026-10-02, from the security review: before, the server could delete any record on every device without detection.)
- **Pull.** `GET /api/sync/records?since=<revision>` returns every record, tombstones included, with a revision above the cursor, in revision order.
- **Push.** The client sends changes, each encrypted with its new `version`. The server accepts a change only if that version is exactly the record's current version plus 1 (1 for a new record), then assigns it the next account `revision` and stores it. A stale change is rejected for that record with the stable error code `version_conflict` and the current record.
- **Conflicts.** For a rejected change, the client decrypts the server's record and compares the `modified_at` times inside the two plaintexts: the newer edit wins. If the local edit wins, the client encrypts it again with the server's version plus 1 and pushes it; otherwise the local change is dropped. A deletion is a change like any other and is kept as a tombstone, so it reaches every device.
- **Clarifications from implementing step 5 (2026-09-30).** A tombstone has no plaintext and so no `modified_at`: between an edit and a concurrent deletion, the edit wins, so no edit is lost; the deleting device can delete again. A record changed on a device stays at the server's version plus 1 however often it is edited before the server accepts it, because the server accepts only the next version. A pulled record at or below the version a device holds is ignored, so a stored version never goes down, and a pulled record that does not decrypt is reported and never replaces anything. A vault used before it had an account uploads each record as version 1 whatever its local version. A pending device may ask for its approval every few seconds: only wrong claim tokens count against the address's sign-in limit.
- The client pulls before it pushes, and after every sign-in, unlock, and reconnect.

## The admin panel

- Administrator accounts are separate from user accounts and cannot hold a vault. They sign in with a password (Argon2id on the server) and a mandatory TOTP code (RFC 6238). TOTP secrets are stored encrypted with the settings encryption key.
- **First-run setup.** A fresh server prints a one-time setup token to its log and accepts the first administrator only with that token, so nobody can claim an exposed fresh server before the operator does.
- Sessions use an `HttpOnly`, `Secure`, `SameSite=Strict` cookie, expire after inactivity, and state-changing requests require a CSRF token.
- Administrators can create, disable, and delete user accounts, revoke devices, turn two-factor sign-in off for an account whose user lost the authenticator, and see metadata (email, created, last seen, device names, record counts, storage used). No API returns ciphertext, wrapped keys, or hashes to the panel, and nothing in the panel can decrypt anything.
- Every administrative action is written to the activity log.
- **Clarifications from implementing step 6 (2026-10-01).** A TOTP code is accepted once, within one 30-second step of drift either way; the last accepted step is stored. The setup token is 192 random bits, kept in memory as a hash, and replaced at each start until the first administrator exists; that administrator is created only after a code from the new TOTP secret is confirmed. Sessions are stored on the server as a hash of the cookie token and end after 30 idle minutes or 12 hours. "Create user accounts" means invitations: an administrator cannot create a vault's keys for a user.

## What a compromised server reveals

An attacker with the full database and the settings encryption key gets email addresses, device names and timestamps, record counts and sizes, Argon2id hashes of `AK` and `RAK`, the wrapped vault keys, and the TOTP secrets of accounts with two-factor sign-in (which takes away that second factor, not the need for `AK`). To read a vault they must guess the master password (each guess costs one Argon2id derivation with the account's parameters) or the recovery key (256 bits, infeasible). They cannot sign in as a user without `AK`, and cannot forge or reorder records without detection.

An attacker who controls the running server can additionally withhold or delay records and see which account syncs when, and could serve a new user a fake pre-login salt. They still never receive the master password or `PK`.

## SSH connections

- Host keys are verified on every connection. The first connection to a host shows its fingerprint (SHA-256) and asks the user to trust it; the trusted key is stored as a record and syncs to every device. A changed host key blocks the connection with a clear warning; the user must explicitly replace the stored key.
- Private keys are stored as records in the vault, never as files outside it. Passphrase-protected keys are decrypted in memory only for the connection.
- Passwords typed for a single connection are not stored unless the user asks.
- Supported key types follow `dartssh2` 4.1: Ed25519, ECDSA (P-256, P-384, P-521), and RSA with SHA-2 signatures.

## Logging

No component logs passwords, keys, tokens, record contents, wrapped keys, or secret settings. Logs may contain account and device identifiers, email addresses for security events, and error codes.

## Open for later

- Hardware-backed SSH keys (FIDO2).
- Sharing records between accounts (teams).
- Raising the Argon2id parameters as hardware improves.
- An independent security review before the project is promoted beyond early adopters.
