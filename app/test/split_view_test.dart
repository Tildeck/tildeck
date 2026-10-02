import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/app.dart';
import 'package:tildeck/server_check.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ui/terminal_panel.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/password_rules.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

void main() {
  testWidgets('two sessions side by side on a wide screen; a click makes the other side active', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-split')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      // Nothing listens on port 1: each session ends at once, which is all a
      // layout needs.
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

    await settle();
    for (final host in vault.hosts) {
      await tester.tap(find.byKey(ValueKey('host-${host.id}')));
      await settle();
      // A wide window has the desktop layout: the sidebar leads back to the hosts.
      await tester.tap(find.byKey(const ValueKey('nav-hosts')));
      await settle();
    }
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await settle();
    expect(find.byType(TerminalPanel), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('splitView')));
    await settle();
    final panels = tester.widgetList<TerminalPanel>(find.byType(TerminalPanel)).toList();
    expect(panels.map((p) => p.session.target.port), [1, 1]);
    expect(panels[0].session, isNot(same(panels[1].session)));

    // Clicking the right side makes it the active one: it moves left.
    final right = panels[1].session;
    await tester.tapAt(tester.getCenter(find.byType(TerminalPanel).last));
    await settle();
    expect(tester.widgetList<TerminalPanel>(find.byType(TerminalPanel)).first.session, same(right));

    await tester.tap(find.byKey(const ValueKey('splitView')));
    await settle();
    expect(find.byType(TerminalPanel), findsOneWidget);
  });
}
