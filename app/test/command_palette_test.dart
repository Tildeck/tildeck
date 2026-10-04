import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/app.dart';
import 'package:tildeck/server_check.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ui/command_palette.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/password_rules.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

void main() {
  test('every word typed must match the name, the detail, or the kind', () {
    final item = PaletteItem(
      icon: Icons.dns,
      title: 'Web 01',
      detail: 'deploy@web-01.example.com',
      kind: 'Connect',
      run: () {},
    );
    expect(item.matches(''), isTrue);
    expect(item.matches('web deploy'), isTrue);
    expect(item.matches('WEB connect'), isTrue);
    expect(item.matches('web staging'), isFalse);
  });

  testWidgets('Ctrl+Shift+P finds a host to connect to and a section to go to', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-palette')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      // Nothing listens on port 1: the session ends at once, which is all
      // the tab needs.
      for (final name in ['Alpha', 'Beta']) {
        await v.put(HostEntry(id: v.newId(), name: name, host: '127.0.0.1', port: 1, username: 'ops', password: 'x'));
      }
      return v;
    }))!;
    await tester.pumpWidget(
      TildeckApp(
        vault: vault,
        commonPasswords: CommonPasswords({}),
        checker: ServerChecker(),
        connector: SshConnector(knownHosts: MemoryKnownHosts()),
        showKeyBar: false,
        initialLocale: const Locale('en'),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    Future<void> palette() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle();
    }

    await settle();
    await palette();
    expect(find.byKey(const ValueKey('paletteQuery')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('paletteQuery')), 'beta');
    await tester.pump();
    Finder inPalette(String text) => find.descendant(of: find.byType(Dialog), matching: find.text(text));
    expect(inPalette('Beta'), findsOneWidget);
    expect(inPalette('Alpha'), findsNothing, reason: 'only what matches');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle();
    expect(find.byKey(const ValueKey('paletteQuery')), findsNothing);
    expect(find.byKey(const ValueKey('tab-0')), findsOneWidget, reason: 'a tab for Beta');
    expect(
      find.descendant(of: find.byKey(const ValueKey('tab-0')), matching: find.text('Beta')),
      findsOneWidget,
      reason: "named by the host, not its address",
    );

    // Arrows choose among the matches; a section opens in place.
    await palette();
    await tester.enterText(find.byKey(const ValueKey('paletteQuery')), 'section');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final second = tester.widget<ListTile>(find.byKey(const ValueKey('paletteItem-1')));
    expect(second.selected, isTrue);
    await tester.enterText(find.byKey(const ValueKey('paletteQuery')), 'identities');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle();
    expect(find.byKey(const ValueKey('addIdentity')), findsOneWidget, reason: 'the identities section');
  });
}
