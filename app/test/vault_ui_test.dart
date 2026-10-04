// The vault through the interface: create it, save a host, lock, refuse a
// wrong password, unlock, and find the host again.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/app.dart';
import 'package:tildeck/server_check.dart';
import 'package:tildeck/vault/password_rules.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ui/hosts_page.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

void main() {
  testWidgets('create, save a host, auto-lock, lock, and unlock', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-ui')))!;
    addTearDown(() => dir.deleteSync(recursive: true));
    final vault = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));

    Future<void> waitFor(bool Function() done, String what) async {
      for (var i = 0; i < 1000; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        // Advance the fake clock too, so route and dialog animations finish.
        await tester.pump(const Duration(milliseconds: 50));
        if (done()) return;
      }
      fail('timed out waiting for $what');
    }

    await tester.pumpWidget(
      TildeckApp(
        vault: vault,
        commonPasswords: CommonPasswords({'1q2w3e4r5t6y'}),
        checker: ServerChecker(),
        connector: SshConnector(knownHosts: MemoryKnownHosts()),
        showKeyBar: false,
        initialLocale: const Locale('en'),
      ),
    );
    await waitFor(() => find.byKey(const ValueKey('createVault')).evaluate().isNotEmpty, 'the create screen');

    // Too short, then a common password, then a good one.
    await tester.enterText(find.byKey(const ValueKey('masterPassword')), 'short');
    await tester.tap(find.byKey(const ValueKey('createVault')));
    await tester.pump();
    expect(find.text('At least 12 characters'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('masterPassword')), '1q2w3e4r5t6y');
    await tester.tap(find.byKey(const ValueKey('createVault')));
    await tester.pump();
    expect(find.text('This password is too common. Choose another one.'), findsOneWidget);

    const password = 'orange-kettle-winter-42';
    await tester.enterText(find.byKey(const ValueKey('masterPassword')), password);
    await tester.enterText(find.byKey(const ValueKey('confirmPassword')), password);
    await tester.tap(find.byKey(const ValueKey('createVault')));
    await waitFor(() => find.byKey(const ValueKey('addHost')).evaluate().isNotEmpty, 'the hosts tab');

    await tester.tap(find.byKey(const ValueKey('addHost')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('hostName')), 'Web 01');
    await tester.enterText(find.byKey(const ValueKey('hostGroup')), 'Production');
    await tester.enterText(find.byKey(const ValueKey('host')), 'prod-web-01.example.com');
    // The editor's list builds lazily: scroll until the sign-in part exists.
    // Save stays in the bar under it.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('username')),
      200,
      scrollable: find.descendant(of: find.byType(HostEditorPage), matching: find.byType(Scrollable)).first,
    );
    await tester.enterText(find.byKey(const ValueKey('username')), 'deploy');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('saveHost')));
    // The editor closes once the host is saved; the list behind it shows it.
    await waitFor(
      () => find.byKey(const ValueKey('saveHost')).evaluate().isEmpty && find.text('Web 01').evaluate().isNotEmpty,
      'the saved host in the list',
    );
    expect(find.text('Production'), findsOneWidget);

    // Auto-lock while a screen with vault data is open on top: the editor,
    // with a password typed into it, must not survive the lock.
    await tester.tap(find.byKey(const ValueKey('addHost')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('hostName')), 'Half-typed secret host');
    await tester.pump(const Duration(minutes: 15, seconds: 1));
    await waitFor(
      () =>
          find.byKey(const ValueKey('unlock')).evaluate().isNotEmpty &&
          find.byKey(const ValueKey('hostName')).evaluate().isEmpty,
      'the unlock screen, with the editor closed, after the idle timer',
    );
    expect(find.byKey(const ValueKey('hostName')), findsNothing, reason: 'screens above the vault close when it locks');
    expect(find.text('Half-typed secret host'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('unlockPassword')), password);
    await tester.tap(find.byKey(const ValueKey('unlock')));
    await waitFor(() => find.text('Web 01').evaluate().isNotEmpty, 'the host after unlocking');

    await tester.tap(find.byKey(const ValueKey('lockVault')));
    await waitFor(() => find.byKey(const ValueKey('unlock')).evaluate().isNotEmpty, 'the unlock screen');
    expect(find.text('Web 01'), findsNothing, reason: 'nothing of the vault shows while locked');

    await tester.enterText(find.byKey(const ValueKey('unlockPassword')), 'not-the-master-password');
    await tester.tap(find.byKey(const ValueKey('unlock')));
    await waitFor(() => find.text('Wrong master password.').evaluate().isNotEmpty, 'the wrong password message');

    await tester.enterText(find.byKey(const ValueKey('unlockPassword')), password);
    await tester.tap(find.byKey(const ValueKey('unlock')));
    await waitFor(() => find.text('Web 01').evaluate().isNotEmpty, 'the host after unlocking');
  });
}
