import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/app.dart';
import 'package:tildeck/server_check.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';
import 'package:tildeck/ui/terminal_panel.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/password_rules.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

void main() {
  testWidgets('the split view holds the terminals put there, sized and arranged by dragging', (tester) async {
    tester.view.physicalSize = const Size(2400, 1000);
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

    List<TerminalPanel> panels() => tester.widgetList<TerminalPanel>(find.byType(TerminalPanel)).toList();
    TerminalSession sessionOf(int tab) => tester
        .widget<TerminalPanel>(
          find.descendant(of: find.byKey(ValueKey('pane-$tab')), matching: find.byType(TerminalPanel)),
        )
        .session;
    // The tabs' sessions, to follow them as they move.
    final sessions = <TerminalSession>[];
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(ValueKey('tab-$i')));
      await settle();
      sessions.add(panels().single.session);
    }
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await settle();
    List<TerminalSession> shown() => [for (final p in panels()) p.session];

    // Turned on, the split view takes the selected terminal and the newest
    // other one, not every terminal open.
    await tester.tap(find.byKey(const ValueKey('splitView')));
    await settle();
    expect(shown(), [sessions[1], sessions[4]]);

    // A tab dropped on a pane's after half goes after it; on its before
    // half, before it.
    Future<void> drop(String from, String to) async {
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(ValueKey(from))));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(tester.getCenter(find.byKey(ValueKey(to))));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await settle();
    }

    await drop('tabDrag-2', 'drop-after-1');
    expect(shown(), [sessions[1], sessions[2], sessions[4]]);
    await drop('tabDrag-3', 'drop-before-1');
    expect(shown(), [sessions[3], sessions[1], sessions[2], sessions[4]]);
    expect(panels().map((p) => p.session.target.port).toSet(), {1});

    // A terminal outside it is shown alone; one inside brings it back.
    await tester.tap(find.byKey(const ValueKey('tab-0')));
    await settle();
    expect(shown(), [sessions[0]]);
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await settle();
    expect(shown(), hasLength(4));

    // The line between two panes is dragged to size them, and a double
    // click makes them even again.
    double width(int tab) => tester.getSize(find.byKey(ValueKey('pane-$tab'))).width;
    double height(int tab) => tester.getSize(find.byKey(ValueKey('pane-$tab'))).height;
    final even = width(3);
    await tester.drag(find.byKey(const ValueKey('columnDivider-0-0')), const Offset(120, 0));
    await settle();
    expect(width(3), closeTo(even + 120, 2));
    expect(width(1), closeTo(even - 120, 2));
    expect(width(2), closeTo(even, 2), reason: 'only the two beside the line');
    await tester.drag(find.byKey(const ValueKey('columnDivider-0-0')), const Offset(2000, 0));
    await settle();
    expect(width(1), closeTo(240, 2), reason: 'the smallest a pane is dragged to');
    await tester.tap(find.byKey(const ValueKey('columnDivider-0-0')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('columnDivider-0-0')));
    await settle();
    expect(width(3), closeTo(even, 2));
    final rowHeight = height(3);
    await tester.drag(find.byKey(const ValueKey('rowDivider-0')), const Offset(0, 80));
    await settle();
    expect(height(3), closeTo(rowHeight + 80, 2));
    expect(height(4), closeTo(rowHeight - 80, 2));

    // A pane's handle moves it to another place, the same way.
    await drop('paneHandle-4', 'drop-before-3');
    expect(shown(), [sessions[4], sessions[3], sessions[1], sessions[2]]);
    expect(sessionOf(4), same(sessions[4]), reason: 'the tabs themselves did not move');

    // Taken out, a terminal stays open as a tab.
    await tester.tap(find.byKey(const ValueKey('paneRemove-2')));
    await settle();
    expect(shown(), [sessions[4], sessions[3], sessions[1]]);
    expect(find.byKey(const ValueKey('tab-2')), findsOneWidget);

    // A tab dropped on a terminal shown alone splits the two.
    await tester.tap(find.byKey(const ValueKey('splitView')));
    await settle();
    expect(shown(), hasLength(1));
    await tester.tap(find.byKey(const ValueKey('tab-0')));
    await settle();
    await drop('tabDrag-2', 'drop-after-0');
    expect(shown(), [sessions[4], sessions[3], sessions[1], sessions[0], sessions[2]]);
  });
}
