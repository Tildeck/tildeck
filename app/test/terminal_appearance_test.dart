import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';
import 'package:tildeck/terminal/terminal_themes.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/terminal_panel.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

Widget app(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.dark),
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

TerminalSession connectedSession() {
  final session = TerminalSession(const ConnectionTarget(host: 'web.example.com', username: 'ops'))
    ..state = SessionState.connected;
  session.terminal.write('error: disk full\r\nok\r\nERROR: retry failed\r\nall done\r\n');
  return session;
}

void main() {
  testWidgets('search finds every match, case-insensitive, and steps through them', (tester) async {
    final session = connectedSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(app(TerminalPanel(session: session, showKeyBar: false, onReconnect: () {})));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('terminalSearch')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('terminalSearchField')), 'error');
    await tester.pump();
    expect(find.text('2 of 2'), findsOneWidget, reason: 'the newest match is current');

    await tester.tap(find.byTooltip('Next match'));
    await tester.pump();
    expect(find.text('1 of 2'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('terminalSearchField')), 'nothing like this');
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);

    await tester.tap(find.byTooltip('Close search'));
    await tester.pump();
    expect(find.byKey(const ValueKey('terminalSearchField')), findsNothing);
  });

  testWidgets('Ctrl with + and - asks for a size within the limits, Ctrl+0 for the default', (tester) async {
    final session = connectedSession();
    addTearDown(session.dispose);
    final asked = <double>[];
    Future<void> pumpAt(double size) => tester.pumpWidget(
      app(
        TerminalPanel(session: session, showKeyBar: false, onReconnect: () {}, fontSize: size, onFontSize: asked.add),
      ),
    );
    await pumpAt(14);
    await tester.pump();
    Future<void> chord(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    await chord(LogicalKeyboardKey.equal);
    await chord(LogicalKeyboardKey.minus);
    await chord(LogicalKeyboardKey.digit0);
    expect(asked, [15, 13, defaultFontSize]);

    asked.clear();
    await pumpAt(maxFontSize);
    await chord(LogicalKeyboardKey.equal);
    expect(asked, [maxFontSize], reason: 'never above the largest size');
  });

  test('every scheme has a unique id, and an unknown id falls back to the default', () {
    final ids = terminalThemes.map((t) => t.id).toSet();
    expect(ids, hasLength(terminalThemes.length));
    expect(themeById('no-such-theme').id, terminalThemes.first.id);
    expect(themeById(null).id, 'tildeck-dark');
  });

  test('preferences are one encrypted record that comes back after a lock', () async {
    final dir = await Directory.systemTemp.createTemp('tildeck-prefs');
    addTearDown(() => dir.delete(recursive: true));
    Vault open() => Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
    final vault = open();
    await vault.load();
    await vault.create('orange-kettle-winter-42');
    expect(vault.preferences.terminalTheme, isNull);
    await vault.put(vault.preferences.copyWith(terminalTheme: 'nord', fontSize: 17));
    await vault.put(vault.preferences.copyWith(fontSize: 18));

    final again = open();
    await again.load();
    await again.unlock('orange-kettle-winter-42');
    expect((again.preferences.terminalTheme, again.preferences.fontSize), ('nord', 18.0));
    expect(again.preferences.id, PreferencesEntry.fixedId);
  });
}
