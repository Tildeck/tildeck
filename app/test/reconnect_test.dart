import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';
import 'package:tildeck/terminal/terminal_options.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/terminal_panel.dart';

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

TerminalSession closed({required ConnectProblem? problem, bool wasConnected = true, int attempt = 0}) =>
    TerminalSession(const ConnectionTarget(host: 'web.example.com', username: 'ops'))
      ..state = SessionState.closed
      ..problem = problem
      ..wasConnected = wasConnected
      ..reconnectAttempt = attempt;

void main() {
  Future<List<int>> pumpPanel(WidgetTester tester, TerminalSession session, {TerminalOptions? options}) async {
    final attempts = <int>[];
    addTearDown(session.dispose);
    await tester.pumpWidget(
      app(
        TerminalPanel(
          // As in the app: one panel per session.
          key: ObjectKey(session),
          session: session,
          showKeyBar: false,
          onReconnect: () {},
          onAutoReconnect: attempts.add,
          options: options ?? const TerminalOptions(),
        ),
      ),
    );
    await tester.pump();
    return attempts;
  }

  testWidgets('a dropped connection reconnects after a short wait, counted down', (tester) async {
    final attempts = await pumpPanel(tester, closed(problem: ConnectProblem.disconnected));
    expect(find.textContaining('Reconnecting in 2 s (1 of 5)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Reconnecting in 1 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(attempts, [1]);
  });

  testWidgets('a failed attempt waits longer for the next, and stops after the last', (tester) async {
    var attempts = await pumpPanel(
      tester,
      closed(problem: ConnectProblem.unreachable, wasConnected: false, attempt: 2),
    );
    expect(find.textContaining('Reconnecting in 10 s (3 of 5)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(attempts, [3]);

    attempts = await pumpPanel(tester, closed(problem: ConnectProblem.timeout, wasConnected: false, attempt: 5));
    await tester.pump(const Duration(seconds: 60));
    expect(attempts, isEmpty, reason: 'five tries, then the user decides');
  });

  testWidgets('no reconnection after an exit, a refused sign-in, a cancel, or with it turned off', (tester) async {
    for (final session in [
      closed(problem: null),
      closed(problem: ConnectProblem.authFailed),
      closed(problem: ConnectProblem.disconnected, wasConnected: false),
    ]) {
      final attempts = await pumpPanel(tester, session);
      await tester.pump(const Duration(seconds: 60));
      expect(attempts, isEmpty, reason: '${session.problem}');
    }

    var attempts = await pumpPanel(tester, closed(problem: ConnectProblem.disconnected));
    await tester.tap(find.byKey(const ValueKey('cancelReconnect')));
    await tester.pump(const Duration(seconds: 60));
    expect(attempts, isEmpty);
    expect(find.byKey(const ValueKey('reconnectNow')), findsOneWidget, reason: 'by hand still');

    attempts = await pumpPanel(
      tester,
      closed(problem: ConnectProblem.disconnected),
      options: const TerminalOptions(autoReconnect: false),
    );
    await tester.pump(const Duration(seconds: 60));
    expect(attempts, isEmpty);
  });
}
