import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/command_history.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

/// Real file work finishes outside the fake clock.
Future<void> waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 1000 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

TerminalSession _session() => TerminalSession(const ConnectionTarget(host: 'web.example.com', username: 'ops'));

void main() {
  test('commands run in a session are kept once each, newest last, never a password', () {
    final session = _session();
    session.line.feed('ls -la\r');
    session.line.feed('  df -h  \r');
    session.line.feed('\r');
    session.line.feed('ls -la\r');
    session.atPasswordPrompt = true;
    session.line.feed('hunter2\r');
    session.atPasswordPrompt = false;
    session.line.feed('cd /tmp\t\r');
    expect(session.commands, ['df -h', 'ls -la'], reason: 'a line changed by Tab completion is not known');

    session.history = ['uptime', 'df -h'];
    expect(recentCommands(session), ['ls -la', 'df -h', 'uptime'], reason: "this session's first, then the server's");
  });

  testWidgets('a recent command is saved as a snippet with it filled in', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-commands')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      return v;
    }))!;
    final session = _session();
    session.line.feed('journalctl -u nginx -f\r');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showCommandHistory(context, vault, session), child: const Text('open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('journalctl -u nginx -f'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('saveCommand-0')));
    await tester.pumpAndSettle();
    final command = find.descendant(of: find.byType(Dialog), matching: find.text('journalctl -u nginx -f'));
    expect(command, findsOneWidget, reason: 'the editor starts with the command');
    await tester.enterText(find.byKey(const ValueKey('snippetName')), 'Follow nginx');
    await tester.tap(find.byKey(const ValueKey('saveSnippet')));
    await waitFor(tester, () => vault.snippets.isNotEmpty);
    expect((vault.snippets.single.name, vault.snippets.single.command), ('Follow nginx', 'journalctl -u nginx -f'));
  });
}
