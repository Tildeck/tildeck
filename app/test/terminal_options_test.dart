import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';
import 'package:tildeck/terminal/terminal_options.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/terminal_panel.dart';
import 'package:tildeck/vault/models.dart';
import 'package:xterm/xterm.dart';

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

TerminalSession connected() =>
    TerminalSession(const ConnectionTarget(host: 'web.example.com', username: 'ops'))..state = SessionState.connected;

void main() {
  test('options come from the preferences, and only valid ones', () {
    const defaults = TerminalOptions();
    final none = TerminalOptions.of(const PreferencesEntry());
    expect(
      (none.fontFamily, none.lineHeight, none.cursor, none.bell, none.scrollback, none.copyOnSelect),
      (defaults.fontFamily, 1.2, TerminalCursorType.block, BellMode.visual, 10000, false),
    );

    final chosen = TerminalOptions.of(
      const PreferencesEntry(
        fontFamily: 'Consolas',
        lineHeight: 1.4,
        cursorStyle: 'bar',
        bell: 'none',
        scrollback: 50000,
        copyOnSelect: true,
      ),
    );
    expect(
      (chosen.fontFamily, chosen.lineHeight, chosen.cursor, chosen.bell, chosen.scrollback, chosen.copyOnSelect),
      ('Consolas', 1.4, TerminalCursorType.verticalBar, BellMode.none, 50000, true),
    );
    expect(chosen.fontFallback, ['JetBrainsMono'], reason: 'a missing system font falls back to the bundled one');

    // From another device or version: out of range, unknown.
    final odd = TerminalOptions.of(
      const PreferencesEntry(lineHeight: 9, cursorStyle: 'blink', bell: 'loud', scrollback: 7),
    );
    expect(
      (odd.lineHeight, odd.cursor, odd.bell, odd.scrollback),
      (1.2, TerminalCursorType.block, BellMode.visual, 10000),
    );
  });

  test('the fonts offered are the bundled one and the system ones', () {
    expect(terminalFonts(windows: true, android: false).map((f) => f.family), [
      'JetBrainsMono',
      'Cascadia Mono',
      'Consolas',
      'Courier New',
    ]);
    expect(terminalFonts(windows: false, android: true).map((f) => f.family), ['JetBrainsMono', 'monospace']);
  });

  testWidgets('a visual bell flashes the screen; with no bell nothing shows', (tester) async {
    final session = connected();
    addTearDown(session.dispose);
    await tester.pumpWidget(app(TerminalPanel(session: session, showKeyBar: false, onReconnect: () {})));
    session.terminal.write('\x07');
    await tester.pump();
    expect(find.byKey(const ValueKey('bellFlash')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('bellFlash')), findsNothing);

    await tester.pumpWidget(
      app(
        TerminalPanel(
          session: session,
          showKeyBar: false,
          onReconnect: () {},
          options: const TerminalOptions(bell: BellMode.none),
        ),
      ),
    );
    session.terminal.write('\x07');
    await tester.pump();
    expect(find.byKey(const ValueKey('bellFlash')), findsNothing);
  });

  testWidgets('the cursor and font follow the options', (tester) async {
    final session = connected();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      app(
        TerminalPanel(
          session: session,
          showKeyBar: false,
          onReconnect: () {},
          options: const TerminalOptions(cursor: TerminalCursorType.underline, fontFamily: 'Consolas', lineHeight: 1.5),
        ),
      ),
    );
    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.cursorType, TerminalCursorType.underline);
    expect((view.textStyle.fontFamily, view.textStyle.height), ('Consolas', 1.5));
    expect(view.textStyle.fontFamilyFallback.first, 'JetBrainsMono');
  });

  testWidgets('copy on select copies a finished selection once', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final session = connected();
    addTearDown(session.dispose);
    session.terminal.write('hello world\r\n');
    await tester.pumpWidget(
      app(
        TerminalPanel(
          session: session,
          showKeyBar: false,
          onReconnect: () {},
          options: const TerminalOptions(copyOnSelect: true),
        ),
      ),
    );
    final buffer = session.terminal.buffer;
    session.controller.setSelection(buffer.createAnchor(0, 0), buffer.createAnchor(5, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(copied, isEmpty, reason: 'not while the selection may still change');
    await tester.pump(const Duration(milliseconds: 400));
    expect(copied, ['hello']);
    session.controller.notifyListeners();
    await tester.pump(const Duration(milliseconds: 400));
    expect(copied, ['hello'], reason: 'the same selection once');
  });
}
