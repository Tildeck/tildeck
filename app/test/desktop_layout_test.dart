import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
