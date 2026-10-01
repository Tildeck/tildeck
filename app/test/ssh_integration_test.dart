// SSH against a real OpenSSH server. scripts/verify.sh starts a throwaway
// server (the `openssh` stage of scripts/toolchain/Dockerfile), generates
// keys, and passes them in the environment. Without that environment these
// tests are skipped, unless TILDECK_REQUIRE_SSH_TESTS is set, which makes a
// missing server a failure so verify can never pass without running them.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/autocomplete.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';

final env = Platform.environment;
final host = env['TILDECK_TEST_SSH_HOST'];
final port = int.tryParse(env['TILDECK_TEST_SSH_PORT'] ?? '') ?? 2222;
final user = env['TILDECK_TEST_SSH_USER'] ?? 'tildeck';
final password = env['TILDECK_TEST_SSH_PASSWORD'];
final key = env['TILDECK_TEST_SSH_KEY'];
final encryptedKey = env['TILDECK_TEST_SSH_KEY_ENCRYPTED'];
final keyPassphrase = env['TILDECK_TEST_SSH_KEY_PASSPHRASE'];

/// Records every host key prompt and answers with [answer].
class PromptLog {
  PromptLog([this.answer = true]);
  final bool answer;
  final statuses = <HostKeyStatus>[];

  Future<bool> call({
    required ConnectionTarget target,
    required KnownHost presented,
    required HostKeyStatus status,
    KnownHost? previous,
  }) async {
    statuses.add(status);
    return answer;
  }
}

Future<ConnectProblem?> problemOf(Future<Object?> attempt) async {
  try {
    await attempt;
    return null;
  } on ConnectException catch (e) {
    return e.problem;
  }
}

void main() {
  final skip = host == null
      ? (env['TILDECK_REQUIRE_SSH_TESTS'] == null ? 'no test SSH server in the environment' : null)
      : null;

  group('SSH', skip: skip, () {
    setUpAll(() {
      if (host == null) fail('TILDECK_REQUIRE_SSH_TESTS is set but no test SSH server was provided.');
    });

    ConnectionTarget target({String? pass, String? privateKey, String? passphrase}) => ConnectionTarget(
      host: host!,
      port: port,
      username: user,
      password: pass,
      privateKey: privateKey,
      passphrase: passphrase,
    );

    test('password sign-in asks to trust a new host once, then remembers it', () async {
      final connector = SshConnector(knownHosts: MemoryKnownHosts());
      final prompts = PromptLog();

      final first = await connector.connect(target(pass: password), promptHostKey: prompts.call);
      expect(utf8.decode(await first.run('echo tildeck-ok')).trim(), 'tildeck-ok');
      first.close();
      expect(prompts.statuses, [HostKeyStatus.unknown]);

      final second = await connector.connect(target(pass: password), promptHostKey: prompts.call);
      second.close();
      expect(prompts.statuses, [HostKeyStatus.unknown], reason: 'a trusted key connects without asking');
    });

    test('a wrong password is an authentication failure', () async {
      final connector = SshConnector(knownHosts: MemoryKnownHosts());
      expect(
        await problemOf(connector.connect(target(pass: 'not-the-password'), promptHostKey: PromptLog().call)),
        ConnectProblem.authFailed,
      );
    });

    test('private key sign-in', () async {
      final connector = SshConnector(knownHosts: MemoryKnownHosts());
      final client = await connector.connect(target(privateKey: key), promptHostKey: PromptLog().call);
      expect(utf8.decode(await client.run('whoami')).trim(), user);
      client.close();
    });

    test('an encrypted key needs its passphrase, and the right one', () async {
      final connector = SshConnector(knownHosts: MemoryKnownHosts());
      expect(
        await problemOf(connector.connect(target(privateKey: encryptedKey), promptHostKey: PromptLog().call)),
        ConnectProblem.keyPassphraseRequired,
      );
      expect(
        await problemOf(
          connector.connect(
            target(privateKey: encryptedKey, passphrase: 'wrong'),
            promptHostKey: PromptLog().call,
          ),
        ),
        ConnectProblem.keyPassphraseWrong,
      );
      final client = await connector.connect(
        target(privateKey: encryptedKey, passphrase: keyPassphrase),
        promptHostKey: PromptLog().call,
      );
      client.close();
    });

    test('a changed host key is never accepted silently, and refusing it cancels the connection', () async {
      final store = MemoryKnownHosts();
      await store.trust(
        host!,
        port,
        const KnownHost(type: 'ssh-ed25519', fingerprint: 'SHA256:not-the-real-key-at-all-aaaaaaaaaaaaaaaaaaaa'),
      );
      final refuse = PromptLog(false);
      expect(
        await problemOf(SshConnector(knownHosts: store).connect(target(pass: password), promptHostKey: refuse.call)),
        ConnectProblem.hostKeyRejected,
      );
      expect(refuse.statuses, [HostKeyStatus.changed]);

      // Replacing the key on purpose connects and trusts the new key.
      final accept = PromptLog();
      final client = await SshConnector(knownHosts: store).connect(target(pass: password), promptHostKey: accept.call);
      client.close();
      expect(accept.statuses, [HostKeyStatus.changed]);
    });

    test('a closed port is unreachable', () async {
      final connector = SshConnector(knownHosts: MemoryKnownHosts(), timeout: const Duration(seconds: 5));
      final closed = ConnectionTarget(host: host!, port: 1, username: user, password: password);
      expect(
        await problemOf(connector.connect(closed, promptHostKey: PromptLog().call)),
        anyOf(ConnectProblem.unreachable, ConnectProblem.timeout),
      );
    });

    test('a terminal session runs an interactive shell', () async {
      final session = TerminalSession(target(pass: password));
      addTearDown(session.dispose);
      session.terminal.resize(100, 30);
      unawaited(session.start(SshConnector(knownHosts: MemoryKnownHosts()), PromptLog().call));

      await _until(() => session.state == SessionState.connected);
      session.terminal.textInput('echo "tildeck-$port-shell"\r');
      await _until(() => session.terminal.buffer.getText().contains('tildeck-$port-shell\n'));

      session.terminal.textInput('exit\r');
      await _until(() => session.state == SessionState.closed);
      expect(session.problem, isNull, reason: 'a shell that exits is a normal close');
    });

    test('suggestions come from the server history, and a password prompt is answered', () async {
      final setup = await SshConnector(
        knownHosts: MemoryKnownHosts(),
      ).connect(target(pass: password), promptHostKey: PromptLog().call);
      await setup.run(r'printf "uptime\nls -la /var/log\nls -la /var/log\n" > ~/.bash_history');
      setup.close();

      final session = TerminalSession(target(pass: password));
      addTearDown(session.dispose);
      session.terminal.resize(100, 30);
      unawaited(session.start(SshConnector(knownHosts: MemoryKnownHosts()), PromptLog().call));
      await _until(() => session.history.contains('ls -la /var/log'));
      expect(session.history.where((c) => c == 'ls -la /var/log'), hasLength(1));

      // Typed, completed from the history, and run.
      session.terminal.textInput('ls -la /var/l');
      expect(suggest(session.line.line!, session.history).first.command, 'ls -la /var/log');
      session.complete('ls -la /var/log');
      session.terminal.textInput('\r');
      await _until(() => session.terminal.buffer.getText().contains('total '));

      // A prompt that asks for a password gets the session's password.
      session.terminal.textInput(
        r'printf "Password: "; read -rs x; echo; echo "got:$x"'
        '\r',
      );
      await _until(() => session.atPasswordPrompt);
      session.fillPassword();
      await _until(() => session.terminal.buffer.getText().contains('got:$password'));
    });

    test('environment variables reach the shell', () async {
      final session = TerminalSession(
        ConnectionTarget(
          host: host!,
          port: port,
          username: user,
          password: password,
          environment: const {'TILDECK_GREETING': 'shalom-42'},
          startupCommand: 'echo "env:\$TILDECK_GREETING"',
        ),
      );
      addTearDown(session.dispose);
      session.terminal.resize(100, 30);
      unawaited(session.start(SshConnector(knownHosts: MemoryKnownHosts()), PromptLog().call));
      await _until(() => session.terminal.buffer.getText().contains('env:shalom-42\n'));
    });

    test('a startup snippet runs when the shell opens, and a snippet runs line by line', () async {
      final session = TerminalSession(
        target(pass: password).withStartupCommand('X=\$((40 + 2))\necho "startup-\$X"\n\n'),
      );
      addTearDown(session.dispose);
      session.terminal.resize(100, 30);
      unawaited(session.start(SshConnector(knownHosts: MemoryKnownHosts()), PromptLog().call));

      await _until(() => session.terminal.buffer.getText().contains('startup-42\n'));
      session.run('cd /tmp\r\npwd');
      await _until(() => session.terminal.buffer.getText().contains('/tmp\n'));
    });
  });
}

Future<void> _until(bool Function() condition, {Duration timeout = const Duration(seconds: 15)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
