// SSH certificates against the throwaway OpenSSH server of scripts/verify.sh
// --area app, which trusts a test authority (/tmp/ca) that the account can
// sign with. A key that is in no authorized_keys signs in with its
// certificate only. Skipped without the server, unless
// TILDECK_REQUIRE_SSH_TESTS is set.
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/certificates.dart';
import 'package:tildeck/ssh/keys.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/vault/vault_crypto.dart';

final env = Platform.environment;
final host = env['TILDECK_TEST_SSH_HOST'];
final port = int.tryParse(env['TILDECK_TEST_SSH_PORT'] ?? '') ?? 2222;
final user = env['TILDECK_TEST_SSH_USER'] ?? 'tildeck';
final password = env['TILDECK_TEST_SSH_PASSWORD'];

Future<bool> trust({
  required ConnectionTarget target,
  required KnownHost presented,
  required HostKeyStatus status,
  KnownHost? previous,
}) async => true;

Future<SSHClient> connect({String? pass, String? key, String? certificate}) =>
    SshConnector(knownHosts: MemoryKnownHosts()).connect(
      ConnectionTarget(
        host: host!,
        port: port,
        username: user,
        password: pass,
        privateKey: key,
        certificate: certificate,
      ),
      promptHostKey: trust,
    );

Future<String> run(SSHClient client, String command) async => utf8.decode(await client.run(command)).trim();

void main() {
  final skip = host == null
      ? (env['TILDECK_REQUIRE_SSH_TESTS'] == null ? 'no test SSH server in the environment' : null)
      : null;

  group('certificates', skip: skip, () {
    late VaultCrypto crypto;
    late SSHClient admin;
    setUpAll(() async {
      if (host == null) fail('TILDECK_REQUIRE_SSH_TESTS is set but no test SSH server was provided.');
      crypto = await VaultCrypto.load();
      admin = await connect(pass: password);
    });
    tearDownAll(() => admin.close());

    /// Has the test authority sign [publicKey] with ssh-keygen's [options].
    Future<String> sign(String publicKey, String options) => run(
      admin,
      "echo '$publicKey' > /tmp/user.pub && rm -f /tmp/user-cert.pub && "
      'ssh-keygen -q -s /tmp/ca -I tildeck-test $options /tmp/user.pub && cat /tmp/user-cert.pub',
    );

    Future<ConnectProblem?> problem(Future<SSHClient> attempt) async {
      try {
        (await attempt).close();
        return null;
      } on ConnectException catch (e) {
        return e.problem;
      }
    }

    for (final kind in KeyKind.values) {
      test(
        'a ${kind.name} key signs in with its certificate, and not without it',
        () async {
          final pem = switch (kind) {
            KeyKind.ed25519 => generateEd25519(crypto.sodium, 'cert'),
            KeyKind.rsa4096 => await generateRsa4096('cert'),
          };
          final info = readKey(pem)!;
          final line = await sign(info.publicKey, '-n $user -V -5m:+1h');

          final certificate = readCertificate(line)!;
          expect(certificate.principals, [user]);
          expect(certificate.keyId, 'tildeck-test');
          expect(certificate.validBefore!.isAfter(DateTime.now()), isTrue);
          expect(certificateMatches(certificate, pem), isTrue);

          expect(await problem(connect(key: pem)), ConnectProblem.authFailed, reason: 'the key alone is not trusted');
          final client = await connect(key: pem, certificate: line);
          addTearDown(client.close);
          expect(await run(client, 'echo signed-in-with-a-certificate'), 'signed-in-with-a-certificate');
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }

    test('a certificate for another user, or an expired one, does not sign in', () async {
      final pem = generateEd25519(crypto.sodium, 'cert');
      final info = readKey(pem)!;

      final otherUser = await sign(info.publicKey, '-n someone-else -V -5m:+1h');
      expect(await problem(connect(key: pem, certificate: otherUser)), ConnectProblem.authFailed);

      final expired = await sign(info.publicKey, '-n $user -V 20200101:20200102');
      expect(readCertificate(expired)!.expiredAt(DateTime.now()), isTrue);
      expect(await problem(connect(key: pem, certificate: expired)), ConnectProblem.authFailed);

      // Another key's certificate is not this key's.
      final other = generateEd25519(crypto.sodium, 'other');
      expect(certificateMatches(readCertificate(otherUser)!, other), isFalse);
    });
  });
}
