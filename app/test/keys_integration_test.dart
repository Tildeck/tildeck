// Keys against the throwaway OpenSSH server of scripts/verify.sh --area app
// (see ssh_integration_test.dart for the environment): a key made here is
// installed with the password, then signs in alone, and OpenSSH's own
// tools read what this client wrote. Skipped without the server, unless
// TILDECK_REQUIRE_SSH_TESTS is set.
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
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

Future<SSHClient> connect({String? pass, String? key}) => SshConnector(knownHosts: MemoryKnownHosts()).connect(
  ConnectionTarget(host: host!, port: port, username: user, password: pass, privateKey: key),
  promptHostKey: trust,
);

Future<String> run(SSHClient client, String command) async => utf8.decode(await client.run(command)).trim();

void main() {
  final skip = host == null
      ? (env['TILDECK_REQUIRE_SSH_TESTS'] == null ? 'no test SSH server in the environment' : null)
      : null;

  group('keys', skip: skip, () {
    late VaultCrypto crypto;
    setUpAll(() async {
      if (host == null) fail('TILDECK_REQUIRE_SSH_TESTS is set but no test SSH server was provided.');
      crypto = await VaultCrypto.load();
    });

    for (final kind in KeyKind.values) {
      test(
        'a new ${kind.name} key is installed with the password, then signs in alone',
        () async {
          final pem = switch (kind) {
            KeyKind.ed25519 => generateEd25519(crypto.sodium, 'tildeck-test'),
            KeyKind.rsa4096 => await generateRsa4096('tildeck-test'),
          };
          final info = readKey(pem, comment: 'tildeck-test')!;

          // Before: the key alone is refused.
          await expectLater(
            connect(key: pem),
            throwsA(isA<ConnectException>().having((e) => e.problem, 'problem', ConnectProblem.authFailed)),
          );

          final admin = await connect(pass: password);
          addTearDown(admin.close);
          expect(await run(admin, installKeyCommand(info.publicKey)), 'tildeck-key-installed');
          expect(await run(admin, installKeyCommand(info.publicKey)), 'tildeck-key-installed');
          final blob = info.publicKey.split(' ')[1];
          expect(await run(admin, 'grep -c "$blob" ~/.ssh/authorized_keys'), '1', reason: 'installed once');

          final byKey = await connect(key: pem);
          addTearDown(byKey.close);
          expect(await run(byKey, 'echo signed-in-with-the-new-key'), 'signed-in-with-the-new-key');

          // OpenSSH agrees on the fingerprint.
          final keygen = await run(admin, "echo '${info.publicKey}' > /tmp/k.pub && ssh-keygen -lf /tmp/k.pub");
          expect(keygen, contains(info.fingerprint));
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }

    test('an exported key with a passphrase opens with ssh-keygen', () async {
      final pem = generateEd25519(crypto.sodium, 'tildeck-export');
      final info = readKey(pem, comment: 'tildeck-export')!;
      final file = exportKey(pem, newPassphrase: 'orange-kettle');
      final admin = await connect(pass: password);
      addTearDown(admin.close);
      final b64 = base64.encode(utf8.encode(file));
      final opened = await run(
        admin,
        'echo $b64 | base64 -d > /tmp/exported && chmod 600 /tmp/exported && '
        'ssh-keygen -y -P orange-kettle -f /tmp/exported',
      );
      expect(opened.split(' ').take(2).join(' '), info.publicKey.split(' ').take(2).join(' '));
      final refused = await run(admin, 'ssh-keygen -y -P wrong -f /tmp/exported 2>&1; echo exit:\$?');
      expect(refused, isNot(contains(info.publicKey.split(' ')[1])));
      expect(refused, isNot(endsWith('exit:0')));
    });
  });
}
