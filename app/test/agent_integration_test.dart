// Agent forwarding against the throwaway OpenSSH server of scripts/verify.sh
// --area app (see ssh_integration_test.dart for the environment). Skipped
// without it, unless TILDECK_REQUIRE_SSH_TESTS is set.
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';

final env = Platform.environment;
final host = env['TILDECK_TEST_SSH_HOST'];
final port = int.tryParse(env['TILDECK_TEST_SSH_PORT'] ?? '') ?? 2222;
final user = env['TILDECK_TEST_SSH_USER'] ?? 'tildeck';
final password = env['TILDECK_TEST_SSH_PASSWORD'];
final key = env['TILDECK_TEST_SSH_KEY'];

/// Signs in with the password, offering [agentKeys] to the server.
Future<SSHClient> connect(List<({String privateKey, String? passphrase})>? agentKeys) =>
    SshConnector(knownHosts: MemoryKnownHosts()).connect(
      ConnectionTarget(host: host!, port: port, username: user, password: password, agentKeys: agentKeys),
      promptHostKey: ({required target, required presented, required status, previous}) async => true,
    );

/// From the server, signs in to itself with whatever the agent offers, and
/// nothing else (no password, no key files).
const onward =
    'ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null '
    '-o IdentityFile=none -o PasswordAuthentication=no 127.0.0.1 echo signed-in-onward 2>&1';

Future<String> runInShell(SSHClient client, String command) async {
  // Each session asks the server for agent forwarding, an exec like a shell.
  final session = await client.execute(command);
  final out = await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
  await session.done;
  return out;
}

void main() {
  final skip = host == null
      ? (env['TILDECK_REQUIRE_SSH_TESTS'] == null ? 'no test SSH server in the environment' : null)
      : null;

  group('agent forwarding', skip: skip, () {
    setUpAll(() {
      if (host == null) fail('TILDECK_REQUIRE_SSH_TESTS is set but no test SSH server was provided.');
    });

    test('the server signs in onward with a key from the vault', () async {
      final client = await connect([(privateKey: 'not a key', passphrase: null), (privateKey: key!, passphrase: null)]);
      addTearDown(client.close);
      expect(await runInShell(client, r'test -n "$SSH_AUTH_SOCK" && echo has-agent'), contains('has-agent'));
      expect(await runInShell(client, onward), contains('signed-in-onward'));
    });

    test('without it, the server has no agent and cannot sign in onward', () async {
      final client = await connect(null);
      addTearDown(client.close);
      expect(await runInShell(client, r'test -z "$SSH_AUTH_SOCK" && echo no-agent'), contains('no-agent'));
      expect(await runInShell(client, onward), isNot(contains('signed-in-onward')));
    });
  });
}
