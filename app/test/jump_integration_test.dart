// Jump hosts against the throwaway OpenSSH server of scripts/verify.sh
// --area app (see ssh_integration_test.dart for the environment): the server
// is its own jump host, reaching itself at 127.0.0.1. Skipped without it,
// unless TILDECK_REQUIRE_SSH_TESTS is set.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';

final env = Platform.environment;
final host = env['TILDECK_TEST_SSH_HOST'];
final port = int.tryParse(env['TILDECK_TEST_SSH_PORT'] ?? '') ?? 2222;
final user = env['TILDECK_TEST_SSH_USER'] ?? 'tildeck';
final password = env['TILDECK_TEST_SSH_PASSWORD'];

ConnectionTarget direct({String? pass}) =>
    ConnectionTarget(host: host!, port: port, username: user, password: pass ?? password);

/// The same server as its own jump host sees it.
ConnectionTarget inside({ConnectionTarget? jump, int targetPort = 2222}) =>
    ConnectionTarget(host: '127.0.0.1', port: targetPort, username: user, password: password, jump: jump);

void main() {
  final skip = host == null
      ? (env['TILDECK_REQUIRE_SSH_TESTS'] == null ? 'no test SSH server in the environment' : null)
      : null;

  group('jump hosts', skip: skip, () {
    setUpAll(() {
      if (host == null) fail('TILDECK_REQUIRE_SSH_TESTS is set but no test SSH server was provided.');
    });

    final prompted = <String>[];
    late SshConnector connector;
    setUp(() {
      prompted.clear();
      connector = SshConnector(knownHosts: MemoryKnownHosts());
    });
    Future<bool> trust({required target, required presented, required status, previous}) async {
      prompted.add('${target.host}:${target.port}');
      return true;
    }

    test('a host is reached through another one', () async {
      final client = await connector.connect(inside(jump: direct()), promptHostKey: trust);
      addTearDown(client.close);
      final out = utf8.decode(await client.run('echo through-the-jump'));
      expect(out.trim(), 'through-the-jump');
      expect(prompted, ['$host:$port', '127.0.0.1:2222'], reason: 'each host key is checked under its own address');
    });

    test('a chain of two jump hosts', () async {
      final client = await connector.connect(
        inside(jump: inside(jump: direct())),
        promptHostKey: trust,
      );
      addTearDown(client.close);
      expect(utf8.decode(await client.run('echo two-hops')).trim(), 'two-hops');
    });

    test('closing the connection closes the tunnel under it', () async {
      final client = await connector.connect(inside(jump: direct()), promptHostKey: trust);
      // Two sshd sessions for this user while connected: the jump and the target.
      Future<int> sessions() async {
        final probe = await SshConnector(knownHosts: MemoryKnownHosts()).connect(direct(), promptHostKey: trust);
        try {
          final out = utf8.decode(await probe.run('pgrep -u $user -f "sshd.*$user" | wc -l'));
          return int.parse(out.trim());
        } finally {
          probe.close();
        }
      }

      final before = await sessions();
      client.close();
      var after = before;
      for (var i = 0; i < 50 && after >= before; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        after = await sessions();
      }
      expect(after, lessThanOrEqualTo(before - 2), reason: 'both the target and the jump connection ended');
    });

    test('a failure at the jump host says so', () async {
      await expectLater(
        connector.connect(
          inside(jump: direct(pass: 'wrong-password')),
          promptHostKey: trust,
        ),
        throwsA(
          isA<ConnectException>()
              .having((e) => e.problem, 'problem', ConnectProblem.authFailed)
              .having((e) => e.via, 'via', direct().label),
        ),
      );
    });

    test('a target the jump host cannot reach is unreachable, at the target', () async {
      await expectLater(
        connector.connect(inside(jump: direct(), targetPort: 1), promptHostKey: trust),
        throwsA(
          isA<ConnectException>()
              .having((e) => e.problem, 'problem', ConnectProblem.unreachable)
              .having((e) => e.via, 'via', isNull),
        ),
      );
    });
  });
}
