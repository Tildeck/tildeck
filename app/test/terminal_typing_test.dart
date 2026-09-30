// The whole path a user takes: fill in the connection form, connect to a
// real OpenSSH server, trust its key, and type into the terminal. Typed text
// must reach the shell. Needs the test SSH server from scripts/verify.sh (see
// ssh_integration_test.dart); skipped without it unless required.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/app.dart';
import 'package:tildeck/server_check.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:xterm/xterm.dart';

final env = Platform.environment;
final host = env['TILDECK_TEST_SSH_HOST'];

void main() {
  final skip = host == null && env['TILDECK_REQUIRE_SSH_TESTS'] == null
      ? 'no test SSH server in the environment'
      : null;

  testWidgets('text typed after connecting from the form reaches the shell', skip: skip != null, (tester) async {
    if (host == null) fail('TILDECK_REQUIRE_SSH_TESTS is set but no test SSH server was provided.');
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TildeckApp(
        checker: ServerChecker(),
        connector: SshConnector(knownHosts: KnownHostsStore.memory()),
        showKeyBar: false,
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    // Filled in field by field, as a person does; the password field is the
    // last one with the keyboard before the connection opens.
    await tester.enterText(find.byKey(const ValueKey('host')), host!);
    await tester.enterText(find.byKey(const ValueKey('port')), env['TILDECK_TEST_SSH_PORT'] ?? '2222');
    await tester.enterText(find.byKey(const ValueKey('username')), env['TILDECK_TEST_SSH_USER'] ?? 'tildeck');
    await tester.enterText(find.byKey(const ValueKey('password')), env['TILDECK_TEST_SSH_PASSWORD']!);
    await tester.tap(find.byKey(const ValueKey('connect')));

    // The network runs in real time; the widget tree is pumped in between.
    Future<void> waitFor(bool Function() done, String what) async {
      for (var i = 0; i < 300; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        if (done()) return;
      }
      fail('timed out waiting for $what');
    }

    await waitFor(() => find.byKey(const ValueKey('trustHostKey')).evaluate().isNotEmpty, 'the host key prompt');
    await tester.tap(find.byKey(const ValueKey('trustHostKey')));
    await tester.pump();

    Terminal terminal() => tester.widget<TerminalView>(find.byType(TerminalView)).terminal;
    await waitFor(
      () => find.byType(TerminalView).evaluate().isNotEmpty && terminal().buffer.getText().contains(r'$'),
      'the shell prompt',
    );

    // Type without clicking the terminal first: after connecting, the
    // terminal must already have the keyboard.
    tester.testTextInput.enterText('echo typed-into-terminal');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    await waitFor(() => terminal().buffer.getText().contains('typed-into-terminal\n'), 'the typed command to run');
  });
}
