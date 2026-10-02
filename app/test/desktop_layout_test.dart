import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ui/hosts_page.dart';

import 'golden_test.dart' show app, sampleVault, settle;

void main() {
  Future<void> show(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vault = (await tester.runAsync(() => sampleVault(unlocked: true)))!;
    await tester.pumpWidget(app(vault, 'en', ThemeMode.light));
    await settle(tester);
  }

  testWidgets('a wide window has a sidebar, and every section opens in place', (tester) async {
    await show(tester, const Size(1280, 800));
    for (final (section, title) in [
      ('keys', 'Keys'),
      ('knownHosts', 'Known hosts'),
      ('forwards', 'Port forwarding'),
      ('snippets', 'Snippets'),
      ('history', 'History'),
      ('appearance', 'Terminal appearance'),
      ('account', 'Sync'),
      ('password', 'Change master password'),
      ('hosts', 'Hosts'),
    ]) {
      await tester.tap(find.byKey(ValueKey('nav-$section')));
      await settle(tester);
      expect(find.text(title), findsWidgets, reason: section);
      // Nothing was pushed over the sidebar: there is no way back to take.
      expect(find.byType(BackButton), findsNothing, reason: section);
      expect(find.byKey(const ValueKey('nav-hosts')), findsOneWidget);
    }
    // The hosts list does not repeat the sidebar's buttons.
    expect(find.byKey(const ValueKey('openSnippets')), findsNothing);
    expect(find.byKey(const ValueKey('openForwards')), findsNothing);
  });

  testWidgets('a narrow window keeps the phone layout', (tester) async {
    await show(tester, const Size(800, 900));
    expect(find.byKey(const ValueKey('nav-hosts')), findsNothing);
    expect(find.byKey(const ValueKey('hostsTab')), findsOneWidget);
    expect(find.byKey(const ValueKey('openSnippets')), findsOneWidget);
  });

  testWidgets('a host is edited in a side panel beside the grid, and offered on a right-click', (tester) async {
    await show(tester, const Size(1440, 900));
    // Right-click a card: its menu.
    await tester.tap(find.byKey(const ValueKey('host-h3')), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hostEdit')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hostEdit')));
    await tester.pumpAndSettle();

    // The editor sits beside the grid, which stays.
    expect(find.byKey(const ValueKey('closePanel')), findsOneWidget);
    expect(find.byKey(const ValueKey('host-h1')), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('hostName')), 'Home NAS');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('saveHost')),
      300,
      scrollable: find.descendant(of: find.byType(HostEditorPage), matching: find.byType(Scrollable)).first,
    );
    await tester.tap(find.byKey(const ValueKey('saveHost')));
    for (var i = 0; i < 1000 && find.byKey(const ValueKey('closePanel')).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byKey(const ValueKey('closePanel')), findsNothing, reason: 'saved and closed');
    expect(find.text('Home NAS'), findsOneWidget);

    // Group settings open in the same place.
    await tester.tap(find.byKey(const ValueKey('groupSettings-Production')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('groupUsername')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('closePanel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('groupUsername')), findsNothing);

    // Quick connect is a dialog, not a page.
    await tester.tap(find.byKey(const ValueKey('quickConnect')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byKey(const ValueKey('host')), findsOneWidget);
  });
}
