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
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/connect_form.dart';
import 'package:tildeck/ui/host_key_dialog.dart';
import 'package:tildeck/ui/sync_server_page.dart';
import 'package:tildeck/ui/terminal_panel.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';
import 'package:xterm/xterm.dart' show TerminalView;

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

    testWidgets('sync server $locale ${mode.name}', (tester) async {
      phone(tester);
      await tester.pumpWidget(screen(locale, mode, SyncServerPage(checker: ServerChecker(client: readyServer))));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'https://sync.example.com');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/sync_server_${locale}_${mode.name}.png'));
    });
  }
}
