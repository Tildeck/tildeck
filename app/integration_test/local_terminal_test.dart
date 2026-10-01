// Local terminals on Windows, over a real ConPTY: run with
// `scripts\windows.ps1 test` (also in CI on the Windows runner). The Linux
// test container has no ConPTY, so these run only here.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tildeck/local/local_shell.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';

Future<bool> trust({
  required ConnectionTarget target,
  required KnownHost presented,
  required HostKeyStatus status,
  KnownHost? previous,
}) async => true;

Future<void> until(TerminalSession session, bool Function() done, String what) async {
  for (var i = 0; i < 300; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('timed out waiting for $what; the screen:\n${session.terminal.buffer.getText().trimRight()}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final shells = Platform.isWindows ? findLocalShells() : const <LocalShell>[];
  LocalShell shell(LocalShellKind kind) => shells.firstWhere((s) => s.kind == kind);

  testWidgets('Windows has Windows PowerShell and Command Prompt', (tester) async {
    expect(shells.map((s) => s.kind), containsAll([LocalShellKind.windowsPowerShell, LocalShellKind.cmd]));
  }, skip: !Platform.isWindows);

  Future<TerminalSession> open(LocalShell s, {int width = 100, int height = 30}) async {
    final session = TerminalSession(ConnectionTarget.local(s, 'test'))..autocomplete = false;
    session.terminal.resize(width, height);
    unawaited(session.start(SshConnector(knownHosts: MemoryKnownHosts()), trust));
    await until(session, () => session.state != SessionState.connecting, 'the shell');
    expect(session.state, SessionState.connected, reason: 'the shell started (problem: ${session.problem})');
    return session;
  }

  testWidgets('Windows PowerShell runs commands, in the home folder, at the terminal size', (tester) async {
    final session = await open(shell(LocalShellKind.windowsPowerShell));
    addTearDown(session.dispose);
    // Only the shell's answers have the sum and the sizes.
    session.run(r'"sum:$(40 + 2) cols:$($Host.UI.RawUI.WindowSize.Width) at:$((Get-Location).Path)"');
    final home = Platform.environment['USERPROFILE']!;
    await until(
      session,
      () => session.terminal.buffer.getText().contains('sum:42 cols:100 at:$home'),
      'the answer',
    );

    session.terminal.resize(80, 24);
    session.run(r'"now:$($Host.UI.RawUI.WindowSize.Width)"');
    await until(session, () => session.terminal.buffer.getText().contains('now:80'), 'the new size');

    session.run('exit');
    await until(session, () => session.state == SessionState.closed, 'the end');
    expect(session.problem, isNull, reason: 'the shell ended on its own');
  }, skip: !Platform.isWindows);

  testWidgets('Command Prompt sees the whole environment', (tester) async {
    final session = await open(shell(LocalShellKind.cmd));
    addTearDown(session.dispose);
    session.run('set /a 40+2 & echo  root:%SystemRoot%');
    final root = Platform.environment['SystemRoot'] ?? Platform.environment['SYSTEMROOT']!;
    await until(session, () => session.terminal.buffer.getText().contains('42 root:$root'), 'the answer');
  }, skip: !Platform.isWindows);
}
