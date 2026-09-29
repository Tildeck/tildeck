# Security policy

Tildeck stores SSH hosts, keys, and credentials. Security reports are welcome and taken seriously.

## Reporting a vulnerability

Report privately through GitHub: [open a private security advisory](https://github.com/Tildeck/tildeck/security/advisories/new). Do not open a public issue, pull request, or discussion about it.

Please include what is affected (client, sync server, or admin panel, and the version), how to reproduce it, and what an attacker could achieve. We will confirm receipt, keep you informed while we work on a fix, and credit you in the release notes unless you prefer otherwise.

## Supported versions

Tildeck has not had its first release yet. Once it has, security fixes go into the latest release.

## Design boundaries

Useful context when assessing a report:

- Plaintext vault contents and keys exist only on the user's devices. The sync server and the admin panel handle only ciphertext and metadata; a way for either to read plaintext is a vulnerability.
- There is no password reset, by design. Account recovery works only with the user's recovery key.
- The server is designed to run behind a TLS-terminating reverse proxy.
