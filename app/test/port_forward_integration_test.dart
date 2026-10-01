// Port forwarding against the throwaway OpenSSH server of
// scripts/verify.sh --area app (see ssh_integration_test.dart for the
// environment). Skipped without it, unless TILDECK_REQUIRE_SSH_TESTS is set.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/port_forwarding.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/vault/models.dart';

final env = Platform.environment;
final host = env['TILDECK_TEST_SSH_HOST'];
final port = int.tryParse(env['TILDECK_TEST_SSH_PORT'] ?? '') ?? 2222;
final user = env['TILDECK_TEST_SSH_USER'] ?? 'tildeck';
final password = env['TILDECK_TEST_SSH_PASSWORD'];

Future<SSHClient> connect() => SshConnector(knownHosts: MemoryKnownHosts()).connect(
  ConnectionTarget(host: host!, port: port, username: user, password: password),
  promptHostKey: ({required target, required presented, required status, previous}) async => true,
);

/// A free port on this machine.
Future<int> freePort() async {
  final s = await ServerSocket.bind('127.0.0.1', 0);
  final p = s.port;
  await s.close();
  return p;
}

/// The first bytes a socket receives, as text.
Future<String> firstBytes(Socket socket) async {
  final data = await socket.first.timeout(const Duration(seconds: 10));
  return utf8.decode(data, allowMalformed: true);
}

void main() {
  final skip = host == null
      ? (env['TILDECK_REQUIRE_SSH_TESTS'] == null ? 'no test SSH server in the environment' : null)
      : null;

  group('port forwarding', skip: skip, () {
    setUpAll(() {
      if (host == null) fail('TILDECK_REQUIRE_SSH_TESTS is set but no test SSH server was provided.');
    });

    test('local: a port here reaches a port as seen from the server', () async {
      final local = await freePort();
      final rule = PortForwardEntry(
        id: 'f1',
        name: 'sshd on the server',
        hostId: 'h',
        bindPort: local,
        destHost: '127.0.0.1',
        destPort: 2222,
      );
      final active = await startForward(rule, await connect());
      addTearDown(active.stop);
      expect(active.boundPort, local);
      final socket = await Socket.connect('127.0.0.1', local);
      addTearDown(socket.destroy);
      expect(await firstBytes(socket), startsWith('SSH-2.0-'), reason: "the server's own sshd answered");
    });

    test('remote: a port on the server reaches a port here', () async {
      final service = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(service.close);
      service.listen((s) {
        s.write('pong-from-here\n');
        s.close();
      });
      const serverPort = 18022;
      final rule = PortForwardEntry(
        id: 'f2',
        name: 'back to me',
        hostId: 'h',
        kind: ForwardKind.remote,
        bindPort: serverPort,
        destHost: '127.0.0.1',
        destPort: service.port,
      );
      final active = await startForward(rule, await connect());
      addTearDown(active.stop);

      final probe = await connect();
      addTearDown(probe.close);
      final out = utf8.decode(await probe.run('nc -w 5 127.0.0.1 $serverPort </dev/null'));
      expect(out, contains('pong-from-here'));
    });

    test('dynamic: a SOCKS5 proxy here whose connections leave from the server', () async {
      final local = await freePort();
      final rule = PortForwardEntry(id: 'f3', name: 'socks', hostId: 'h', kind: ForwardKind.dynamic, bindPort: local);
      final active = await startForward(rule, await connect());
      addTearDown(active.stop);

      final socket = await Socket.connect('127.0.0.1', local);
      addTearDown(socket.destroy);
      final replies = StreamIterator(socket);
      Future<List<int>> read() async {
        expect(await replies.moveNext().timeout(const Duration(seconds: 10)), isTrue);
        return replies.current;
      }

      socket.add([5, 1, 0]); // SOCKS5, one method: no authentication
      expect(await read(), [5, 0]);
      // CONNECT 127.0.0.1:2222, as the server sees it.
      socket.add([5, 1, 0, 1, 127, 0, 0, 1, 2222 >> 8, 2222 & 0xff]);
      var reply = await read();
      expect(reply.take(2), [5, 0], reason: 'the proxy connected');
      // The reply may already carry the start of the banner.
      var text = utf8.decode(reply.skip(10).toList(), allowMalformed: true);
      while (!text.contains('SSH-2.0-')) {
        reply = await read();
        text += utf8.decode(reply, allowMalformed: true);
      }
      expect(text, contains('SSH-2.0-'));
    });

    test('a port that is taken is reported', () async {
      final taken = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(taken.close);
      final rule = PortForwardEntry(
        id: 'f4',
        name: 'taken',
        hostId: 'h',
        bindPort: taken.port,
        destHost: 'x',
        destPort: 1,
      );
      await expectLater(
        startForward(rule, await connect()),
        throwsA(isA<ForwardException>().having((e) => e.problem, 'problem', ForwardProblem.portInUse)),
      );
    });
  });
}
