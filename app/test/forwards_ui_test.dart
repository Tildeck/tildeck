import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/port_forwarding.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/port_forwards_page.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

Widget page(Vault vault, ForwardManager manager) => MaterialApp(
  theme: buildTheme(Brightness.light),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: PortForwardsPage(
    vault: vault,
    manager: manager,
    connect: (_, _) async => throw const SocketException('unreachable'),
  ),
);

/// Real file and network work finishes outside the fake clock.
Future<void> waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 1000 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

void main() {
  test('a rule is stored as data and read back', () {
    const rule = PortForwardEntry(
      id: 'f1',
      name: 'Socks',
      hostId: 'h1',
      kind: ForwardKind.dynamic,
      bindHost: '0.0.0.0',
      bindPort: 1080,
    );
    final back = VaultEntry.fromJson('f1', rule.type, rule.dataJson()) as PortForwardEntry;
    expect(back.kind, ForwardKind.dynamic);
    expect(back.bindHost, '0.0.0.0');
    expect(back.bindPort, 1080);
    expect(back.summary, 'SOCKS5 0.0.0.0:1080');
    const local = PortForwardEntry(id: 'f2', name: 'db', hostId: 'h1', bindPort: 5433, destHost: 'db', destPort: 5432);
    expect(local.summary, '5433 → db:5432');
  });

  testWidgets('a rule is added in the editor, and a failure to start is shown', (tester) async {
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-forwards')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      await v.put(const HostEntry(id: 'h1', name: 'Web 01', host: 'web.example.com', username: 'deploy'));
      return v;
    }))!;
    final manager = ForwardManager();
    addTearDown(manager.dispose);
    await tester.pumpWidget(page(vault, manager));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('addForward')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('forwardName')), 'Postgres');
    await tester.enterText(find.byKey(const ValueKey('forwardBindPort')), '99999');
    await tester.enterText(find.byKey(const ValueKey('forwardDestPort')), '5432');
    await tester.tap(find.byKey(const ValueKey('saveForward')));
    await tester.pumpAndSettle();
    expect(vault.forwards, isEmpty, reason: 'an invalid port is not saved');

    await tester.enterText(find.byKey(const ValueKey('forwardBindPort')), '5433');
    await tester.tap(find.byKey(const ValueKey('saveForward')));
    await waitFor(tester, () => find.byKey(const ValueKey('saveForward')).evaluate().isEmpty);
    final rule = vault.forwards.single;
    expect(rule.hostId, 'h1');
    expect(rule.kind, ForwardKind.local);
    expect(rule.bindHost, '127.0.0.1', reason: 'only this device by default');
    expect(rule.summary, '5433 → localhost:5432');
    expect(find.byKey(const ValueKey('forward-Postgres')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('forwardSwitch-Postgres')));
    await waitFor(tester, () => manager.problemOf(rule.id) != null);
    expect(manager.active(rule.id), isNull);
    expect(manager.problemOf(rule.id), ForwardProblem.connectFailed);
    final status = tester.widget<Text>(find.byKey(const ValueKey('forwardStatus-Postgres')));
    expect(status.data, contains('Could not connect to the host.'));
  });
}
