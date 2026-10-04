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

    // The line between two panes is dragged to size them, and a double
    // click makes them even again.
    double width(int i) => tester.getSize(find.byKey(ValueKey('pane-$i'))).width;
    double height(int i) => tester.getSize(find.byKey(ValueKey('pane-$i'))).height;
    final even = width(0);
    await tester.drag(find.byKey(const ValueKey('columnDivider-0-0')), const Offset(120, 0));
    await settle();
    expect(width(0), closeTo(even + 120, 2));
    expect(width(1), closeTo(even - 120, 2));
    expect(width(2), closeTo(even, 2), reason: 'only the two beside the line');
    // Never smaller than the smallest share.
    await tester.drag(find.byKey(const ValueKey('columnDivider-0-0')), const Offset(2000, 0));
    await settle();
    expect(width(1), closeTo(240, 2), reason: 'the smallest a pane is dragged to');
    await tester.tap(find.byKey(const ValueKey('columnDivider-0-0')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('columnDivider-0-0')));
    await settle();
    expect(width(0), closeTo(even, 2));
    // Rows too.
    final rowHeight = height(0);
    await tester.drag(find.byKey(const ValueKey('rowDivider-0')), const Offset(0, 80));
    await settle();
    expect(height(0), closeTo(rowHeight + 80, 2));
    expect(height(4), closeTo(rowHeight - 80, 2));

    // A pane's handle dropped on another pane swaps the two.
    final first = panels()[0].session;
    final last = panels()[4].session;
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('paneHandle-0'))));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey('pane-4'))));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await settle();
    expect(panels()[0].session, same(last));
    expect(panels()[4].session, same(first));
    expect(border(4), 2, reason: 'the pane that was moved is the active one, where it went');

    await tester.tap(find.byKey(const ValueKey('splitView')));
    await settle();
    expect(panels(), hasLength(1));
    expect(panels().single.session, same(first), reason: 'the active pane stays');
  });
}
