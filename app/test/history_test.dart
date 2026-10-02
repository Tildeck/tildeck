import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/history_recorder.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

late Directory dir;

Future<Vault> newVault() async {
  final vault = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
  await vault.load();
  await vault.create('orange-kettle-winter-42');
  return vault;
}

/// Moves a session to [state], as its connection would.
void moveTo(TerminalSession session, SessionState state, {ConnectProblem? problem}) {
  session
    ..state = state
    ..problem = problem
    // Any change notifies; renaming to nothing changes nothing else.
    ..rename(null);
}

void main() {
  setUp(() async => dir = await Directory.systemTemp.createTemp('tildeck-history'));
  tearDown(() => dir.delete(recursive: true));

  test('a session is logged when it connects and closed off when it ends', () async {
    final vault = await newVault();
    var clock = DateTime.utc(2026, 10, 1, 9);
    final session = TerminalSession(const ConnectionTarget(host: 'web.example.com', username: 'ops', hostId: 'h1'));
    recordHistory(vault, session, now: () => clock);

    moveTo(session, SessionState.connected);
    await vault.flush();
    expect(vault.history.single.endedAt, isNull);
    expect(vault.history.single.hostId, 'h1');

    clock = clock.add(const Duration(minutes: 42));
    moveTo(session, SessionState.closed);
    await vault.flush();
    final entry = vault.history.single;
    expect(entry.endedAt!.difference(entry.startedAt), const Duration(minutes: 42));
    expect(entry.failed, isFalse);
    expect(entry.label, 'ops@web.example.com');
  });

  test('a connection that never opened is logged as failed', () async {
    final vault = await newVault();
    final session = TerminalSession(const ConnectionTarget(host: 'down.example.com', username: 'ops'));
    recordHistory(vault, session);
    moveTo(session, SessionState.closed, problem: ConnectProblem.unreachable);
    await vault.flush();
    expect(vault.history.single.failed, isTrue);
  });

  test('the history keeps the newest connections up to its limit', () async {
    final vault = await newVault();
    final start = DateTime.utc(2026, 1, 1);
    for (var i = 0; i < Vault.historyLimit + 3; i++) {
      await vault.logConnection(
        ConnectionLogEntry(
          id: vault.newId(),
          label: 'c$i',
          startedAt: start.add(Duration(minutes: i)),
        ),
      );
    }
    final history = vault.history;
    expect(history, hasLength(Vault.historyLimit));
    expect(history.first.label, 'c${Vault.historyLimit + 2}', reason: 'newest first');
    expect(history.last.label, 'c3', reason: 'the three oldest are gone');
    // Hundreds of encrypted saves: slow on a loaded machine.
  }, timeout: const Timeout(Duration(minutes: 3)));
}
