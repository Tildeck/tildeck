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
  testWidgets('every terminal in a grid on a wide screen; a click makes a pane the active one', (tester) async {
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
      for (final name in ['Alpha', 'Beta', 'Gamma', 'Delta', 'Epsilon']) {
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
    List<TerminalPanel> panels() => tester.widgetList<TerminalPanel>(find.byType(TerminalPanel)).toList();
    expect(panels(), hasLength(5));
    expect(panels().map((p) => p.session.target.port).toSet(), {1});
    // Three columns: the first row has three panes, the second two, wider.
    final top = tester.getSize(find.byKey(const ValueKey('pane-0')));
    final bottom = tester.getSize(find.byKey(const ValueKey('pane-4')));
    expect(bottom.width, greaterThan(top.width));
    expect(tester.getTopLeft(find.byKey(const ValueKey('pane-3'))).dy, greaterThan(0));

    // A click makes a pane active; the panes keep their places.
    double border(int i) =>
        ((tester.widget<Container>(find.byKey(ValueKey('pane-$i'))).foregroundDecoration! as BoxDecoration).border!
                as Border)
            .top
            .width;
    expect((border(1), border(3)), (2, 1));
    final third = panels()[3].session;
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('pane-3'))));
    await settle();
    expect((border(1), border(3)), (1, 2));
    expect(panels()[3].session, same(third));

    await tester.tap(find.byKey(const ValueKey('splitView')));
    await settle();
    expect(panels(), hasLength(1));
    expect(panels().single.session, same(third), reason: 'the active pane stays');
  });
}
