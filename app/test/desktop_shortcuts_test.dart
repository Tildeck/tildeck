import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/app.dart';
import 'package:tildeck/server_check.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/password_rules.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

void main() {
  testWidgets('tabs by keyboard and mouse, a new connection, the shortcuts list, and the lock', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-keys')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      // Nothing listens on port 1: each session ends at once, which is all
      // the tabs need.
      for (final name in ['Alpha', 'Beta', 'Gamma']) {
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

    Future<void> keys(List<LogicalKeyboardKey> held, LogicalKeyboardKey key) async {
      for (final k in held) {
        await tester.sendKeyDownEvent(k);
      }
      await tester.sendKeyEvent(key);
      for (final k in held.reversed) {
        await tester.sendKeyUpEvent(k);
      }
      await settle();
    }

    const ctrl = LogicalKeyboardKey.controlLeft, shift = LogicalKeyboardKey.shiftLeft;
    int tabs() => find.byKey(const ValueKey('tab-0')).evaluate().isEmpty
        ? 0
        : List.generate(9, (i) => i).where((i) => find.byKey(ValueKey('tab-$i')).evaluate().isNotEmpty).length;

    /// The tab drawn as chosen, or -1 for the hosts.
    int chosen() {
      for (var i = 0; i < tabs(); i++) {
        final shape = tester.widget<Material>(find.byKey(ValueKey('tab-$i'))).shape! as RoundedRectangleBorder;
        if (shape.side.color == tester.element(find.byKey(ValueKey('tab-$i'))).colors.brand) {
          return i;
        }
      }
      return -1;
    }

    await settle();
    for (final host in vault.hosts) {
      await tester.tap(find.byKey(ValueKey('host-${host.id}')));
      await settle();
      await tester.tap(find.byKey(const ValueKey('nav-hosts')));
      await settle();
    }
    expect(tabs(), 3);

    // Ctrl+Tab goes round: hosts, then each tab, then the hosts again; the
    // terminal in the chosen tab does not keep the keys.
    await keys([ctrl], LogicalKeyboardKey.tab);
    expect(chosen(), 0);
    await keys([ctrl], LogicalKeyboardKey.tab);
    expect(chosen(), 1);
    await keys([ctrl, shift], LogicalKeyboardKey.tab);
    expect(chosen(), 0);

    // Ctrl+Shift+W closes the chosen tab.
    await keys([ctrl, shift], LogicalKeyboardKey.keyW);
    expect(tabs(), 2);

    // A middle click closes a tab; a right-click offers closing the others.
    await tester.tap(find.byKey(const ValueKey('tab-1')), buttons: kMiddleMouseButton);
    await settle();
    expect(tabs(), 1);
    await tester.tap(find.byKey(const ValueKey('nav-hosts')));
    await settle();
    await tester.tap(find.byKey(ValueKey('host-${vault.hosts.first.id}')));
    await settle();
    expect(tabs(), 2);
    await tester.tap(find.byKey(const ValueKey('tab-0')), buttons: kSecondaryButton);
    await settle();
    await tester.tap(find.byKey(const ValueKey('tabCloseOthers')));
    await settle();
    expect(tabs(), 1);

    // Ctrl+Shift+T: the hosts, typing into their search.
    await keys([ctrl, shift], LogicalKeyboardKey.keyT);
    expect(chosen(), -1);
    final search = tester.widget<TextField>(find.byKey(const ValueKey('hostSearch')));
    expect(search.focusNode!.hasFocus, isTrue);

    // Ctrl+/ lists the shortcuts.
    await keys([ctrl], LogicalKeyboardKey.slash);
    expect(find.text('Keyboard shortcuts'), findsWidgets);
    await tester.tap(find.text('Close').last);
    await settle();

    // A host's files open as a tab beside the terminals, not as a page.
    final before = tabs();
    await tester.tap(find.byKey(ValueKey('hostMenu-${vault.hosts.first.id}')));
    await settle();
    await tester.tap(find.byKey(const ValueKey('hostFiles')));
    await settle();
    expect(tabs(), before + 1);
    expect(chosen(), before);
    expect(find.byKey(const ValueKey('filesUpload')), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);

    // Ctrl+Shift+L locks.
    await keys([ctrl, shift], LogicalKeyboardKey.keyL);
    expect(vault.status, VaultStatus.locked);
  });
}
