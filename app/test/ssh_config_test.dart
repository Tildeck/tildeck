import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/keys.dart';
import 'package:tildeck/ssh/local_files.dart';
import 'package:tildeck/ssh/ssh_config.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/import_hosts.dart';
import 'package:tildeck/vault/host_import.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

const config = '''
# Work
Host bastion
    HostName bastion.example.com
    User jump
    Port 2222

Host web-01 web-02
  HostName %h.internal
  ProxyJump bastion
  IdentityFile ~/.ssh/id_ed25519

Host db
  HostName=db.internal
  User "postgres admin"
  ProxyJump jump@bastion:2222,other

Match host *.internal
  User ignored

Host *.example.com !secret.example.com
  User example

Host *
  User me
  IdentityFile ~/.ssh/id_rsa
  Port 22
''';

class NoFiles implements LocalFiles {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('named hosts, with the first value of each option across matching blocks', () {
    final hosts = {for (final h in parseSshConfig(config)) h.alias: h};
    expect(hosts.keys, ['bastion', 'web-01', 'web-02', 'db'], reason: 'wildcards and negations name no host');

    final bastion = hosts['bastion']!;
    expect((bastion.address, bastion.user, bastion.port), ('bastion.example.com', 'jump', 2222));
    expect(bastion.identityFiles, ['~/.ssh/id_rsa'], reason: 'from Host *');

    final web = hosts['web-02']!;
    expect((web.user, web.port, web.proxyJump), ('me', 22, 'bastion'));
    expect(web.identityFiles, ['~/.ssh/id_ed25519', '~/.ssh/id_rsa'], reason: 'identity files add up, in order');

    final db = hosts['db']!;
    expect((db.address, db.user), ('db.internal', 'postgres admin'), reason: '= and quotes; Match is not followed');
    expect(db.proxyJump, 'jump@bastion:2222', reason: 'the first hop');
  });

  test('ProxyJump none means none', () {
    final [host] = parseSshConfig('Host a\n  ProxyJump none\n');
    expect(host.proxyJump, isNull);
    expect(host.address, 'a');
  });

  group('importing', () {
    late Directory dir;
    late Vault vault;
    late String ed25519;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('tildeck-import');
      vault = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await vault.load();
      await vault.create('orange-kettle-winter-42');
      ed25519 = generateEd25519(vault.crypto.sodium, 'test');
    });
    tearDown(() => dir.delete(recursive: true));

    test('hosts with their keys and jump hosts; an unreadable key leaves a password', () async {
      final read = <String>[];
      final result = await importSshHosts(
        vault,
        parseSshConfig(config),
        readFile: (path) async {
          read.add(path);
          return path.endsWith('id_ed25519') ? ed25519 : null;
        },
        defaultUser: 'local',
      );
      expect((result.hosts, result.keys), (4, 1));
      expect(result.unreadableKeys, ['~/.ssh/id_rsa']);
      expect(read.toSet().length, read.length, reason: 'each key file read once');

      final byName = {for (final h in vault.hosts) h.name: h};
      final web = byName['web-01']!;
      expect((web.host, web.username, web.auth), ('web-01.internal', 'me', HostAuth.key), reason: '%h is the name');
      expect(vault.entry<KeyEntry>(web.keyId)!.name, 'id_ed25519');
      expect(web.jumpHostId, byName['bastion']!.id);
      expect(byName['db']!.jumpHostId, byName['bastion']!.id, reason: 'user@host:port names the host');
      expect(byName['bastion']!.auth, HostAuth.password, reason: 'its only key could not be read');

      // The same key again is not added twice; a saved host is recognized.
      final again = await importSshHosts(
        vault,
        parseSshConfig('Host other\n  HostName o\n  IdentityFile k\n  ProxyJump bastion\n'),
        readFile: (_) async => ed25519,
        defaultUser: 'local',
      );
      expect(again.keys, 0);
      expect(vault.keys, hasLength(1));
      final other = vault.hosts.firstWhere((h) => h.name == 'other');
      expect(other.jumpHostId, byName['bastion']!.id, reason: 'a saved host by name');
      expect(other.username, 'local', reason: "ssh's default: this computer's user");
      expect(alreadySaved(vault, parseSshConfig('Host x\n HostName o\n').single, 'local'), isTrue);
    });
  });

  testWidgets('the import dialog lists the hosts, skips saved ones, and saves the chosen', (tester) async {
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-import-ui')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      await v.put(
        const HostEntry(id: 'h1', name: 'Bastion', host: 'bastion.example.com', port: 2222, username: 'jump'),
      );
      return v;
    }))!;
    final configFile = File('${dir.path}/config')..writeAsStringSync(config);
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold();
          },
        ),
      ),
    );
    // HOME points at a folder whose .ssh/config is the sample.
    Directory('${dir.path}/.ssh').createSync();
    configFile.copySync('${dir.path}/.ssh/config');
    final source = SshConfigSource(files: NoFiles(), environment: {'HOME': dir.path, 'USER': 'local'});
    final done = showImportHosts(context, vault, source: source);
    for (var i = 0; i < 2000 && find.byKey(const ValueKey('import-db')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      // Advances the test clock too, so dialogs finish opening and closing.
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Already saved'), findsOneWidget, reason: 'bastion is saved');
    expect(find.text('Import 3 hosts'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-web-02')));
    await tester.pump();
    expect(find.text('Import 2 hosts'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('importHostsConfirm')));
    for (var i = 0; i < 2000 && find.byKey(const ValueKey('importHostsConfirm')).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      // Advances the test clock too, so dialogs finish opening and closing.
      await tester.pump(const Duration(milliseconds: 20));
    }
    final result = (await tester.runAsync(() => done))!;
    expect(result.hosts, 2);
    expect(vault.hosts.map((h) => h.name).toSet(), {'Bastion', 'web-01', 'db'});
  });
}
