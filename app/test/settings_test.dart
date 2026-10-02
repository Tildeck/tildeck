import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/server_check.dart';
import 'package:tildeck/settings/device_settings.dart';
import 'package:tildeck/sync/account_service.dart';
import 'package:tildeck/sync/sync_engine.dart';
import 'package:tildeck/sync/sync_server.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/account_page.dart';
import 'package:tildeck/ui/settings_page.dart';
import 'package:tildeck/ui/vault_gate.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/password_rules.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

import 'fake_sync_server.dart';

const password = 'orange-kettle-winter-42';

Widget app(Widget home) => MaterialApp(
  theme: buildTheme(Brightness.light),
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

SyncServices services(Vault vault) {
  final server = FakeSyncServer();
  final engine = SyncEngine(
    vault: vault,
    serverFor: (address) => SyncServer(address, client: server.client),
    changeDelay: const Duration(days: 1),
    interval: const Duration(days: 1),
  );
  return SyncServices(
    vault: vault,
    engine: engine,
    accounts: AccountService(vault: vault, engine: engine),
    checker: ServerChecker(client: server.client),
    commonPasswords: CommonPasswords({}),
  );
}

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('tildeck-settings'));
  tearDown(() => dir.delete(recursive: true));

  Future<Vault> openVault(WidgetTester tester) async => (await tester.runAsync(() async {
    final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
    await v.load();
    await v.create(password);
    return v;
  }))!;

  test("this device's settings survive a restart, and a file from elsewhere never stops the app", () async {
    final file = File('${dir.path}/settings.json');
    final store = DeviceSettingsStore(resolveFile: () async => file);
    await store.load();
    expect(store.value, const DeviceSettings());
    await store.update(
      const DeviceSettings(
        locale: Locale('he'),
        themeMode: ThemeMode.dark,
        backgroundLock: BackgroundLock.never,
        blockScreenshots: true,
      ),
    );
    final again = DeviceSettingsStore(resolveFile: () async => file);
    await again.load();
    expect(again.value, store.value);

    await file.writeAsString('{"locale": "fr", "theme": "neon", "background_lock": 7, "block_screenshots": "yes"}');
    await again.load();
    expect(again.value, const DeviceSettings());
    await file.writeAsString('not json');
    await again.load();
    expect(again.value, const DeviceSettings());
  });

  test('a synced lock time is only ever one of the choices', () {
    PreferencesEntry from(Object? minutes) =>
        PreferencesEntry.fromJson(PreferencesEntry.fixedId, {'auto_lock_minutes': minutes});
    expect(from(30).autoLock, const Duration(minutes: 30));
    for (final bad in [0, 7, 100000, -1, '15', null]) {
      expect(from(bad).autoLock, const Duration(minutes: 15), reason: '$bad');
    }
  });

  testWidgets('settings are saved together with one bar, or put back', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vault = await openVault(tester);
    final store = DeviceSettingsStore();
    await tester.pumpWidget(app(SettingsPage(vault: vault, settings: store, sync: services(vault))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('saveBar')), findsNothing);

    // A change in one group and another in a second group: one bar.
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('saveBar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-security')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('autoLock-5')));
    await tester.pumpAndSettle();
    expect(store.value.themeMode, ThemeMode.system, reason: 'nothing is stored before saving');
    expect(vault.preferences.autoLockMinutes, isNull);

    // Put back: nothing changed.
    await tester.tap(find.byKey(const ValueKey('discardSettings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('saveBar')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings-general')));
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<ThemeMode>>(find.byKey(const ValueKey('themeChoice'))).selected, {
      ThemeMode.system,
    });

    // Saved: this device's settings and the vault's preferences.
    await tester.tap(find.text('Dark'));
    await tester.tap(find.byKey(const ValueKey('settings-security')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('autoLock-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('saveSettings')));
    // Saving encrypts the preferences off the test clock.
    for (var i = 0; i < 500 && find.byKey(const ValueKey('saveBar')).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(store.value.themeMode, ThemeMode.dark);
    expect(vault.preferences.autoLockMinutes, 5);
    expect(find.byKey(const ValueKey('saveBar')), findsNothing);

    // Phone-only options stay off the desktop.
    expect(find.byKey(const ValueKey('blockScreenshots')), findsNothing);
  });

  testWidgets("the vault locks after the preferences' time without activity", (tester) async {
    final vault = await openVault(tester);
    await tester.runAsync(() => vault.put(vault.preferences.copyWith(autoLockMinutes: 5)));
    await tester.pumpWidget(
      app(
        VaultGate(
          vault: vault,
          commonPasswords: CommonPasswords({}),
          unlocked: (_) => const Scaffold(body: Text('open')),
        ),
      ),
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(minutes: 4, seconds: 50));
    expect(vault.status, VaultStatus.unlocked);
    await tester.pump(const Duration(seconds: 11));
    expect(vault.status, VaultStatus.locked);
  });

  testWidgets('going to the background locks as this device is set to', (tester) async {
    final vault = await openVault(tester);
    final store = DeviceSettingsStore(initial: const DeviceSettings(backgroundLock: BackgroundLock.never));
    await tester.pumpWidget(
      app(
        VaultGate(
          vault: vault,
          settings: store,
          commonPasswords: CommonPasswords({}),
          unlocked: (_) => const Scaffold(body: Text('open')),
        ),
      ),
    );
    void away() {
      for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    void back() {
      for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    away();
    back();
    expect(vault.status, VaultStatus.unlocked, reason: 'never');

    await store.update(const DeviceSettings(backgroundLock: BackgroundLock.immediately));
    away();
    expect(vault.status, VaultStatus.locked, reason: 'immediately');
    back();
  });
}
