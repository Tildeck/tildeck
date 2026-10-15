# Teams: shared vaults (design)

Status: Proposed, 2026-10-02, for Shlomi's approval. Shlomi approved writing this design and nothing more: no code depends on it until he approves it, and it changes docs/security-model.md only when it is approved.

Termius Team shares hosts, keys, identities, snippets, and port forwards among the members of a team, with roles, and lets each member keep a personal vault beside it. This document designs the same for Tildeck while keeping what docs/security-model.md promises: the server and its operator never see plaintext, cannot change a vault without detection, and a member who leaves loses access to what changes after they leave.

## What users get

- A **team** is a group of accounts on one server, created by any account and administered by its owners. An account belongs to any number of teams.
- A team has one or more **shared vaults** ("Production", "Customers"). Each holds the same kinds of entries as a personal vault. A member sees their personal vault and every shared vault they are given, side by side: the hosts list shows a vault switcher and, in "All vaults", a badge on each host for its vault.
- **Roles per shared vault:** *reader* (uses entries: connects, runs snippets; cannot see saved passwords or private keys in the editor, though the app uses them to connect, see "What readers can and cannot do"), *editor* (adds and changes entries), *manager* (also adds and removes members of that vault). Team **owners** create shared vaults and manage team membership.
- **Moving and copying:** an entry can be copied from the personal vault into a shared one (and back, by editors). A host in a shared vault can use an identity from the same vault only, so a shared host never points at someone's personal key.
- **Invitations:** an owner or manager invites an existing account by email; the invited member accepts in the app. Admins of the server keep doing what they do today; they cannot read team vaults any more than personal ones.

## Keys

Each shared vault has its own random vault key `SVK`, used exactly like `VK` is today (records sealed under it with the same associated data, with the shared vault's own `vault_id`). What is new is how a member obtains `SVK`.

| Key | Created | Protected by | Where it lives | Sent to the server |
|---|---|---|---|---|
| Account key pair `AKP` (X25519) | Once per account, at the first use of teams | The private half is sealed under the member's personal `VK` | The personal vault (synced like any record) | The public half, signed (below); the private half only sealed |
| Shared vault key `SVK` | When a shared vault is created, and again at every rotation | Sealed to each member's `AKP` public key | The server, one sealed copy per member and generation | Only sealed |

- **Sealing to a member:** `crypto_box_seal(SVK || generation || shared vault_id, member public key)`; the member opens it with the private half of their `AKP` and checks the vault id and generation inside.
- **Knowing whose key it is:** the server could hand an inviting member its own public key instead of the invitee's. To make that detectable, each `AKP` public key is published with its fingerprint (BLAKE2b, 128 bits, shown as words), and the invitation shows the invitee's fingerprint to the person inviting, who can compare it with what the invitee sees in their own app, the way Signal safety numbers work. An app remembers the fingerprints it has seen per account (trust on first use) and warns loudly when a member's key changes. A team that skips the comparison is protected against a passive server, not against an active one that substitutes keys at the first invitation; the app says so where the comparison is offered.
- **Rotation on removal:** removing a member, or downgrading one, makes a new generation of `SVK`. The manager's app re-seals the new `SVK` to every remaining member and re-encrypts records lazily: a record is re-encrypted under the new generation the next time it changes, and the manager's app re-encrypts the rest in the background. Until a record is re-encrypted the removed member could still read its old version from a copy they kept, which is unavoidable: they already saw it. They cannot read anything written after their removal.
- **Records name their generation** in their metadata, so a device knows which `SVK` opens them; old generations are kept (sealed) for records not yet re-encrypted, and deleted once none is left.

## Roles are enforced where they can be

- **Editors and managers** are enforced by the server, which accepts a push to a shared vault only from a device of a member with that role, and by every member's app, which refuses a pulled record that the member list, as of its version, says its author could not write. To make the second check possible, each record in a shared vault carries the author's account id and an Ed25519 signature by the author's account signing key (a second key in `AKP`, published the same way) over the record's ciphertext, id, version, and generation.
- **Readers** receive `SVK`, so the secrets inside entries are readable by their app, which needs them to connect. The app hides saved passwords and private keys from readers in the editor and in exports, as Termius does, but a determined reader could extract them from a device they control. This is stated plainly in the app and in this document: read access to a shared host means access to its credentials. Teams that need to hide credentials from people should give those people their own credentials on the servers instead.
- **Membership changes** are records too: a team's member list lives in a shared, signed log of membership events (add, change role, remove), each signed by an owner or manager whose own membership the log proves. Every app replays the log and checks it, so the server cannot add a member, or raise a role, on its own; it can only withhold events, which shows as an app that does not see a change made elsewhere.

## The server

- New tables: teams, team members (account, role), shared vaults, shared vault access (account, role, the sealed `SVK` per generation), the membership log, and the published public keys. Records keep their table and gain a `vault` column; an account's records are its personal vault (`vault` empty).
- Sync works per vault: pull and push take a vault id; revision cursors are per vault and per device. The server checks the caller's role for pushes and returns only vaults the caller can read.
- The admin panel lists teams and their members (metadata only), can remove an account from a team, and cannot add one: adding needs a key only a member's app has.
- Rate limits and the activity log extend to invitations, role changes, and removals.

## The app

- The vault in memory becomes several vaults: the personal one, unlocked with the master password, and each shared vault, opened with its `SVK` once the personal vault is open. Locking locks all of them.
- The hosts list, keys, identities, snippets, and port forwards show a vault switcher, "All vaults" by default; editors are where they are today, with a vault field.
- A Team section in Settings (desktop sidebar) lists teams, members, roles, invitations, and each member's key fingerprint to compare.

## Recovery and leaving

- Recovery of a personal vault (with the recovery key) brings back the `AKP` private half, sealed in it, so team access survives a forgotten master password.
- An account that leaves a team, or is deleted, loses access at the next rotation; owners are warned that a team with a single owner cannot recover from that owner's loss, and asked to keep two.

## What it does not do

- No sharing with people who have no account on the same server.
- No per-entry permissions inside a shared vault: a vault is the unit of access, as in Termius.
- No hiding of credentials from readers (above).

## Phases, if approved

1. `AKP` in personal vaults, public key publication and fingerprints, and the membership log, with tests against forged and withheld events.
2. Shared vaults with one generation: create, invite, accept, sync per vault, roles enforced by the server and checked by apps.
3. Removal with rotation and lazy re-encryption; readers' restrictions in the UI.
4. Admin panel views, activity log entries, and the app's Team section.

Each phase is its own pull request with tests, after this document and the matching change to docs/security-model.md are approved.

## Open questions for Shlomi

1. Is "a reader can extract credentials from their own device" acceptable, stated openly, as Termius does in practice?
2. Should an admin of the server be able to see that a team exists and who is in it (metadata), as above, or should even that be hidden?
3. Are two owners per team required, or only recommended?
