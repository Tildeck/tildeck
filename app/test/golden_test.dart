// Golden images of the client's screens in English LTR and Hebrew RTL, light
// and dark, rendered with the bundled fonts. They are the reviewable
// screenshots of the app: test/goldens/*.png.
//
// Regenerate after an intended visual change, inside the Flutter toolchain
// container only (fonts render differently elsewhere):
//   flutter test --update-goldens test/golden_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tildeck/app.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/server_check.dart';
import 'package:tildeck/vault/password_rules.dart';
import 'package:tildeck/ssh/file_browser.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';
import 'package:tildeck/sync/account_service.dart';
import 'package:tildeck/sync/sync_engine.dart';
import 'package:tildeck/sync/sync_server.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/connect_form.dart';
import 'package:tildeck/ui/files_page.dart';
import 'package:tildeck/ui/group_editor_page.dart';
import 'package:tildeck/ui/history_page.dart';
import 'package:tildeck/ui/host_key_dialog.dart';
import 'package:tildeck/ui/password_pages.dart';
import 'package:tildeck/ui/snippets_page.dart';
import 'package:tildeck/ui/terminal_settings_page.dart';
import 'package:tildeck/ui/account_page.dart';
import 'package:tildeck/ui/terminal_panel.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';
import 'package:xterm/xterm.dart' show TerminalView;

import 'fake_sync_server.dart';

Future<void> loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }

  await load('Heebo', [
    for (final w in ['Regular', 'Medium', 'Bold', 'ExtraBold']) 'assets/fonts/Heebo-$w.ttf',
  ]);
  await load('JetBrainsMono', [
    for (final w in ['Regular', 'Bold']) 'assets/fonts/jetbrains-mono/JetBrainsMono-$w.ttf',
  ]);

  // Material icons ship with the SDK; tests otherwise draw them as boxes.
  final sdk =
      Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
  final icons = File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) await load('MaterialIcons', [icons.path]);
}

/// A common Android phone: 412x915 logical pixels.
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(412 * 2, 915 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

/// The app's localization and themes around a single screen.
Widget screen(String locale, ThemeMode mode, Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildTheme(Brightness.light),
  darkTheme: buildTheme(Brightness.dark),
  themeMode: mode,
  locale: Locale(locale),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: child,
);

final readyServer = MockClient((request) async {
  final body = request.url.path == '/api/info'
      ? {'name': 'tildeck', 'version': '0.1.0', 'protocol_version': kProtocolVersion}
      : {'status': 'ok', 'database': 'ok', 'error': null};
  return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
});

const sampleTarget = ConnectionTarget(host: 'prod-web-01.example.com', username: 'deploy');

/// A shell session as it looks mid-work, without a network.
TerminalSession sampleSession() {
  final session = TerminalSession(sampleTarget)..state = SessionState.connected;
  session.terminal.write(
    'Welcome to Ubuntu 26.04 LTS (GNU/Linux 6.14.0-15-generic x86_64)\r\n\r\n'
    '\x1b[1;32mdeploy@prod-web-01\x1b[0m:\x1b[1;34m~\x1b[0m\$ systemctl status nginx --no-pager\r\n'
    '\x1b[1;32m\u25cf\x1b[0m nginx.service - A high performance web server\r\n'
    '     Loaded: loaded (/usr/lib/systemd/system/nginx.service; enabled)\r\n'
    '     Active: \x1b[1;32mactive (running)\x1b[0m since Tue 2026-09-29 08:12:44 UTC\r\n'
    '   Main PID: 1204 (nginx)\r\n\r\n'
    '\x1b[1;32mdeploy@prod-web-01\x1b[0m:\x1b[1;34m~\x1b[0m\$ ',
  );
  return session;
}

/// A vault with sample hosts in two groups, unlocked or locked.
Future<Vault> sampleVault({required bool unlocked}) async {
  final dir = await Directory.systemTemp.createTemp('tildeck-golden');
  final vault = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
  await vault.load();
  await vault.create('orange-kettle-winter-42');
  const key = KeyEntry(id: 'k1', name: 'Laptop Ed25519', privateKey: 'x');
  await vault.put(key);
  for (final h in const [
    HostEntry(
      id: 'h1',
      name: 'Web 01',
      group: 'Production',
      host: 'prod-web-01.example.com',
      username: 'deploy',
      auth: HostAuth.key,
      keyId: 'k1',
      tags: ['nginx', 'eu-west'],
    ),
    HostEntry(
      id: 'h2',
      name: 'Database',
      group: 'Production',
      host: 'db.internal.example.com',
      port: 2222,
      username: 'postgres',
    ),
    HostEntry(id: 'h3', name: 'Home server', group: 'Home', host: '192.168.1.20', username: 'shlomi'),
    HostEntry(id: 'h4', name: 'Build box', host: 'ci.example.com', username: 'runner'),
  ]) {
    await vault.put(h);
  }
  if (!unlocked) vault.lock();
  return vault;
}

Widget app(Vault vault, String locale, ThemeMode mode) => TildeckApp(
  vault: vault,
  commonPasswords: CommonPasswords({'1q2w3e4r5t6y'}),
  checker: ServerChecker(client: readyServer),
  connector: SshConnector(knownHosts: MemoryKnownHosts()),
  showKeyBar: false,
  initialLocale: Locale(locale),
  initialThemeMode: mode,
);

/// A folder as it looks mid-work, without a server.
class SampleBrowser extends FileBrowser {
  SampleBrowser() : super(() => throw UnimplementedError());

  @override
  Future<void> start() async {
    path = '/home/deploy/releases';
    final at = DateTime(2026, 9, 30, 14, 5);
    entries = [
      RemoteEntry(
        name: 'current',
        path: '/home/deploy/releases/current',
        isDirectory: true,
        isLink: true,
        modified: at,
      ),
      RemoteEntry(name: 'v1.4.2', path: '/home/deploy/releases/v1.4.2', isDirectory: true, isLink: false, modified: at),
      RemoteEntry(
        name: 'deploy.log',
        path: '/home/deploy/releases/deploy.log',
        isDirectory: false,
        isLink: false,
        size: 48213,
        modified: at,
      ),
      RemoteEntry(
        name: 'app-v1.4.2.tar.gz',
        path: '/home/deploy/releases/app-v1.4.2.tar.gz',
        isDirectory: false,
        isLink: false,
        size: 18874368,
        modified: at,
      ),
    ];
    transfers
      ..add(Transfer('app-v1.4.3.tar.gz', TransferDirection.upload, 20000000)..done = 13000000)
      ..add(
        Transfer('deploy.log', TransferDirection.download, 48213)
          ..done = 48213
          ..state = TransferState.done,
      );
    notifyListeners();
  }
}

/// Sync for [vault] against an in-memory server; syncing only on request.
SyncServices syncServices(Vault vault, FakeSyncServer server) {
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
    commonPasswords: CommonPasswords({'1q2w3e4r5t6y'}),
  );
}

/// Lets asset loading and the first frames finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(loadFonts);

  for (final locale in ['en', 'he']) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('hosts $locale ${mode.name}', (tester) async {
        phone(tester);
        final vault = (await tester.runAsync(() => sampleVault(unlocked: true)))!;
        await tester.pumpWidget(app(vault, locale, mode));
        await settle(tester);
        final dir = tester.widget<Directionality>(find.byType(Directionality).first).textDirection;
        expect(dir, locale == 'he' ? TextDirection.rtl : TextDirection.ltr);
        await expectLater(find.byType(TildeckApp), matchesGoldenFile('goldens/hosts_${locale}_${mode.name}.png'));
      });

      testWidgets('quick connect form $locale ${mode.name}', (tester) async {
        phone(tester);
        await tester.pumpWidget(screen(locale, mode, Scaffold(body: ConnectForm(onConnect: (_) {}))));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('host')), sampleTarget.host);
        await tester.enterText(find.byKey(const ValueKey('username')), sampleTarget.username);
        await tester.pumpAndSettle();
        // Hosts and usernames stay LTR in both languages.
        expect(
          tester
              .widget<EditableText>(
                find.descendant(of: find.byKey(const ValueKey('host')), matching: find.byType(EditableText)),
              )
              .textDirection,
          TextDirection.ltr,
        );
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/connect_${locale}_${mode.name}.png'));
      });
    }
  }

  for (final (locale, mode, name) in [
    ('en', ThemeMode.light, 'create'),
    ('he', ThemeMode.dark, 'create'),
    ('en', ThemeMode.dark, 'unlock'),
    ('he', ThemeMode.light, 'unlock'),
  ]) {
    testWidgets('$name vault $locale ${mode.name}', (tester) async {
      phone(tester);
      final vault = (await tester.runAsync(() async {
        if (name == 'unlock') return sampleVault(unlocked: false);
        final v = Vault(
          crypto: VaultCrypto.load(),
          resolveFile: () async => File('${Directory.systemTemp.createTempSync('tildeck-golden').path}/vault.json'),
        );
        await v.load();
        return v;
      }))!;
      await tester.pumpWidget(app(vault, locale, mode));
      await settle(tester);
      await expectLater(find.byType(TildeckApp), matchesGoldenFile('goldens/${name}_vault_${locale}_${mode.name}.png'));
    });
  }

  for (final (locale, mode) in [('en', ThemeMode.light), ('he', ThemeMode.dark)]) {
    testWidgets('terminal with key bar $locale ${mode.name}', (tester) async {
      phone(tester);
      final session = sampleSession();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        screen(
          locale,
          mode,
          Scaffold(
            body: TerminalPanel(session: session, showKeyBar: true, onReconnect: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The terminal is LTR even inside a Hebrew interface.
      expect(Directionality.of(tester.element(find.byType(TerminalView))), TextDirection.ltr);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/terminal_${locale}_${mode.name}.png'));
    });

    testWidgets('changed host key $locale ${mode.name}', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        screen(
          locale,
          mode,
          const Scaffold(
            body: HostKeyDialog(
              target: sampleTarget,
              status: HostKeyStatus.changed,
              previous: KnownHost(
                type: 'ssh-ed25519',
                fingerprint: 'SHA256:3kDbQ0yq8pZs1m8o5kqf2m5bN7r0A9dEo6wQz1cX4sY',
              ),
              presented: KnownHost(
                type: 'ssh-ed25519',
                fingerprint: 'SHA256:Vt9QwLr2bH6cN1xZs0pK4yF8mE3uJ7aG5dR2oW9nT1k',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/host_key_changed_${locale}_${mode.name}.png'),
      );
    });

    testWidgets('sync sign in $locale ${mode.name}', (tester) async {
      phone(tester);
      final server = FakeSyncServer();
      final services = (await tester.runAsync(() async => syncServices(await sampleVault(unlocked: true), server)))!;
      await tester.pumpWidget(screen(locale, mode, AccountPage(services: services)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('syncAddress')), 'https://sync.example.com');
      await tester.enterText(find.byKey(const ValueKey('syncEmail')), 'shlomi@example.com');
      await tester.enterText(find.byKey(const ValueKey('syncDeviceName')), 'Office PC');
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/sync_sign_in_${locale}_${mode.name}.png'));
    });

    testWidgets('recovery key $locale ${mode.name}', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        screen(
          locale,
          mode,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: RecoveryKeyView(
                recoveryKey: 'K7QD-2M9X-VH4T-8RWC-ZP3N-6YJB-F1GE-5SAK-0T8M-QW2D-HX7C-9VNR-4BJP-E6F',
                onDone: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/recovery_key_${locale}_${mode.name}.png'));
    });

    testWidgets('sync signed in $locale ${mode.name}', (tester) async {
      phone(tester);
      final server = FakeSyncServer()
        ..account = {'email': 'shlomi@example.com'}
        ..devices['me'] = {'id': 'me', 'name': 'Office PC', 'status': 'active', 'token': 'token-a'}
        ..devices['laptop'] = {'id': 'laptop', 'name': 'Travel laptop', 'status': 'active', 'token': 'token-l'}
        ..devices['phone'] = {'id': 'phone', 'name': 'Pixel 9', 'status': 'pending', 'token': 'token-p'};
      final services = (await tester.runAsync(() async {
        final vault = await sampleVault(unlocked: true);
        await vault.setAccount(
          const SyncAccount(
            server: 'https://sync.example.com',
            email: 'shlomi@example.com',
            deviceId: 'me',
            deviceName: 'Office PC',
            token: 'token-a',
          ),
        );
        return syncServices(vault, server);
      }))!;
      services.engine.lastSynced = DateTime.utc(2026, 9, 30, 14, 5);
      await tester.pumpWidget(screen(locale, mode, AccountPage(services: services)));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(find.byKey(const ValueKey('approve-phone')), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sync_signed_in_${locale}_${mode.name}.png'),
      );
    });

    testWidgets('recover and change password $locale ${mode.name}', (tester) async {
      phone(tester);
      final services = (await tester.runAsync(
        () async => syncServices(await sampleVault(unlocked: true), FakeSyncServer()),
      ))!;
      await tester.pumpWidget(screen(locale, mode, RecoveryPage(services: services)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('recoverAddress')), 'https://sync.example.com');
      await tester.enterText(find.byKey(const ValueKey('recoverEmail')), 'shlomi@example.com');
      await tester.enterText(
        find.byKey(const ValueKey('recoverKey')),
        'K7QD-2M9X-VH4T-8RWC-ZP3N-6YJB-F1GE-5SAK-0T8M-QW2D-HX7C-9VNR-4BJP-E6F',
      );
      // The default device name is the machine's: fixed here for a stable image.
      await tester.enterText(find.byKey(const ValueKey('recoverDeviceName')), 'Office PC');
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/recover_${locale}_${mode.name}.png'));

      await tester.pumpWidget(screen(locale, mode, ChangePasswordPage(services: services)));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/change_password_${locale}_${mode.name}.png'),
      );
    });

    testWidgets('files $locale ${mode.name}', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        screen(locale, mode, FilesPage(browser: SampleBrowser(), title: 'deploy@prod-web-01.example.com')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/files_${locale}_${mode.name}.png'));
    });

    testWidgets('snippets $locale ${mode.name}', (tester) async {
      phone(tester);
      final vault = (await tester.runAsync(() async {
        final v = await sampleVault(unlocked: true);
        await v.put(const SnippetEntry(id: 's1', name: 'Restart web', command: 'sudo systemctl restart nginx'));
        await v.put(const SnippetEntry(id: 's2', name: 'Disk usage', command: 'df -h\ndu -sh /var/log/*'));
        await v.put(const SnippetEntry(id: 's3', name: 'Tail app log', command: 'tail -f /var/log/app/current.log'));
        return v;
      }))!;
      await tester.pumpWidget(screen(locale, mode, SnippetsPage(vault: vault)));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/snippets_${locale}_${mode.name}.png'));
    });

    testWidgets('group settings $locale ${mode.name}', (tester) async {
      phone(tester);
      final vault = (await tester.runAsync(() async {
        final v = await sampleVault(unlocked: true);
        await v.put(
          const GroupEntry(id: 'g1', name: 'Production', username: 'deploy', keyId: 'k1', env: {'LANG': 'en_US.UTF-8'}),
        );
        return v;
      }))!;
      await tester.pumpWidget(screen(locale, mode, GroupEditorPage(vault: vault, name: 'Production')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/group_settings_${locale}_${mode.name}.png'),
      );
    });

    testWidgets('terminal appearance $locale ${mode.name}', (tester) async {
      phone(tester);
      final vault = (await tester.runAsync(() async {
        final v = await sampleVault(unlocked: true);
        await v.put(v.preferences.copyWith(terminalTheme: 'solarized-dark', fontSize: 15));
        return v;
      }))!;
      await tester.pumpWidget(screen(locale, mode, TerminalSettingsPage(vault: vault)));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/terminal_appearance_${locale}_${mode.name}.png'),
      );
    });

    testWidgets('terminal search $locale ${mode.name}', (tester) async {
      phone(tester);
      final session = sampleSession();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        screen(
          locale,
          mode,
          Scaffold(
            body: TerminalPanel(session: session, showKeyBar: false, onReconnect: () {}),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('terminalSearch')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('terminalSearchField')), 'nginx');
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/terminal_search_${locale}_${mode.name}.png'),
      );
    });

    testWidgets('history $locale ${mode.name}', (tester) async {
      phone(tester);
      final vault = (await tester.runAsync(() async {
        final v = await sampleVault(unlocked: true);
        final at = DateTime.utc(2026, 9, 30, 9);
        await v.put(
          ConnectionLogEntry(
            id: v.newId(),
            hostId: 'h1',
            label: 'deploy@prod-web-01.example.com',
            startedAt: at,
            endedAt: at.add(const Duration(hours: 1, minutes: 12)),
            device: 'Office PC',
          ),
        );
        await v.put(
          ConnectionLogEntry(
            id: v.newId(),
            hostId: 'h2',
            label: 'postgres@db.internal.example.com:2222',
            startedAt: at.add(const Duration(hours: 3)),
            endedAt: at.add(const Duration(hours: 3, minutes: 4)),
            device: 'Pixel 9',
          ),
        );
        await v.put(
          ConnectionLogEntry(
            id: v.newId(),
            label: 'root@10.0.0.7',
            startedAt: at.add(const Duration(hours: 5)),
            endedAt: at.add(const Duration(hours: 5, seconds: 3)),
            failed: true,
          ),
        );
        return v;
      }))!;
      await tester.pumpWidget(screen(locale, mode, HistoryPage(vault: vault, onReconnect: (_) {})));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/history_${locale}_${mode.name}.png'));
    });

    testWidgets('waiting for approval $locale ${mode.name}', (tester) async {
      phone(tester);
      final server = FakeSyncServer();
      final pending = (await tester.runAsync(() async {
        final first = syncServices(await sampleVault(unlocked: true), server);
        await first.accounts.register(
          address: 'https://sync.example.com',
          email: 'shlomi@example.com',
          password: 'orange-kettle-winter-42',
          locale: 'en',
          deviceName: 'Office PC',
        );
        first.engine.dispose();
        final dir = await Directory.systemTemp.createTemp('tildeck-golden');
        final empty = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
        await empty.load();
        return syncServices(empty, server).accounts.signIn(
          address: 'https://sync.example.com',
          email: 'shlomi@example.com',
          password: 'orange-kettle-winter-42',
          deviceName: 'Pixel 9',
        );
      }))!;
      addTearDown(pending.abandon);
      await tester.pumpWidget(
        screen(
          locale,
          mode,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: PendingDeviceView(pending: pending, deviceName: pending.deviceName, onDone: () {}),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/sync_waiting_${locale}_${mode.name}.png'));
    });
  }
}
