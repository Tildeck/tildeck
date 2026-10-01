// Telnet against the throwaway BusyBox telnetd of scripts/verify.sh --area
// app, which gives a shell without signing in, on the same network as the
// test OpenSSH server. Skipped without it, unless TILDECK_REQUIRE_SSH_TESTS
// is set.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';

final env = Platform.environment;
final telnetHost = env['TILDECK_TEST_TELNET_HOST'];
final telnetPort = int.tryParse(env['TILDECK_TEST_TELNET_PORT'] ?? '') ?? 2323;
final sshHost = env['TILDECK_TEST_SSH_HOST'];
final sshPort = int.tryParse(env['TILDECK_TEST_SSH_PORT'] ?? '') ?? 2222;
final sshUser = env['TILDECK_TEST_SSH_USER'] ?? 'tildeck';
final sshPassword = env['TILDECK_TEST_SSH_PASSWORD'];

Future<bool> trust({
  required ConnectionTarget target,
  required KnownHost presented,
  required HostKeyStatus status,
  KnownHost? previous,
}) async => true;

Future<void> until(bool Function() done, String what, [TerminalSession? session]) async {
  for (var i = 0; i < 200; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  final shown = session == null ? '' : '; the screen:\n${session.terminal.buffer.getText().trimRight()}';
  fail('timed out waiting for $what$shown');
}

void main() {
  final skip = telnetHost == null
      ? (env['TILDECK_REQUIRE_SSH_TESTS'] == null ? 'no test Telnet server in the environment' : null)
      : null;

  group('Telnet', skip: skip, () {
    setUpAll(() {
      if (telnetHost == null) fail('TILDECK_REQUIRE_SSH_TESTS is set but no test Telnet server was provided.');
    });

    Future<TerminalSession> open(ConnectionTarget target) async {
      final session = TerminalSession(target)..autocomplete = false;
      addTearDown(session.dispose);
      session.terminal.resize(100, 30);
      unawaited(session.start(SshConnector(knownHosts: MemoryKnownHosts()), trust));
      await until(() => session.state == SessionState.connected, 'the connection');
      return session;
    }

    String screen(TerminalSession s) => s.terminal.buffer.getText();

    // BusyBox telnetd asks for the window size but not the terminal type;
    // telnet_test.dart covers that negotiation.
    test('a shell over Telnet, with the window size it was told', () async {
      final session = await open(
        ConnectionTarget(host: telnetHost!, port: telnetPort, username: '', protocol: ConnectionProtocol.telnet),
      );
      expect(session.isSsh, isFalse);
      session.run(r'echo "size:$(stty size)"');
      await until(() => screen(session).contains('size:30 100'), 'the window size', session);

      session.terminal.resize(90, 20);
      session.run(r'echo "now:$(stty size)"');
      await until(() => screen(session).contains('now:20 90'), 'the new size', session);
    });

    test('Telnet through an SSH jump host', () async {
      final jump = ConnectionTarget(host: sshHost!, port: sshPort, username: sshUser, password: sshPassword);
      final session = await open(
        ConnectionTarget(
          host: telnetHost!,
          port: telnetPort,
          username: '',
          protocol: ConnectionProtocol.telnet,
          jump: jump,
        ),
      );
      // Only the shell's answer has the sum; the command line has its parts.
      session.run(r'echo "through-$((40 + 2))"');
      await until(() => screen(session).contains('through-42\n'), 'the command through the jump host', session);
    });

    test('a closed port is unreachable', () async {
      final session = TerminalSession(
        ConnectionTarget(host: telnetHost!, port: 1, username: '', protocol: ConnectionProtocol.telnet),
      );
      addTearDown(session.dispose);
      await session.start(SshConnector(knownHosts: MemoryKnownHosts()), trust);
      expect(session.problem, ConnectProblem.unreachable);
    });
  });
}
