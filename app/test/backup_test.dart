import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/local_files.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/backup_page.dart';
import 'package:tildeck/vault/backup.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

const password = 'orange-kettle-winter-42';
const other = 'lantern-river-autumn-77';

/// Downloads into a folder, and hands back the file written last when a file
/// is picked.
class FolderFiles implements LocalFiles {
  FolderFiles(this.dir);

  final Directory dir;
  File? last;

  @override
  Future<File> downloadTarget(String name) async => last = File('${dir.path}/$name');

  @override
  Future<String?> keep(File downloaded, String name) async => downloaded.path;

  @override
  Future<List<PickedFile>> pickToUpload() async {
    final file = last!;
    return [PickedFile(file.uri.pathSegments.last, await file.length(), file.openRead)];
  }

  @override
  bool get folders => true;

  @override
  Future<Directory> folderTarget(String name) => throw UnimplementedError();

  @override
  Future<Directory?> pickFolderToUpload() => throw UnimplementedError();
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('tildeck-backup'));
  tearDown(() => dir.delete(recursive: true));

  Future<Vault> vaultNamed(String name, String secret) async {
    final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/$name.json'));
    await v.load();
    await v.create(secret);
    return v;
  }

  test('a backup opens with its master password into another vault, adding only what is new', () async {
    final a = await vaultNamed('a', password);
    await a.put(const HostEntry(id: 'h1', name: 'Database', host: 'db.example.com', username: 'ops'));
    await a.put(const KeyEntry(id: 'k1', name: 'Ops key', privateKey: 'KEY-MATERIAL'));
    await a.put(const HostEntry(id: 'h2', name: 'Gone', host: 'gone.example.com', username: 'x'));
    await a.delete('h2');
    await a.setAccount(
      const SyncAccount(
        server: 'https://s.example.test',
        email: 'e@example.test',
        deviceId: 'd',
        deviceName: 'n',
        token: 'SECRET-TOKEN',
      ),
    );
    final text = exportBackup(a);
    expect(text, isNot(contains('SECRET-TOKEN')));
    expect(text, isNot(contains('db.example.com')), reason: 'records stay encrypted');
    expect(text, isNot(contains('KEY-MATERIAL')));
    expect((jsonDecode(text) as Map).containsKey('account'), isFalse);

    final crypto = await VaultCrypto.load();
    await expectLater(
      readBackup(text, 'not-the-password-123', crypto),
      throwsA(isA<BackupException>().having((e) => e.problem, 'problem', BackupProblem.wrongPassword)),
    );
    final entries = await readBackup(text, password, crypto);
    expect(entries.map((e) => e.id).toSet(), {'h1', 'k1'}, reason: 'a deleted host is not in it');

    final b = await vaultNamed('b', other);
    await b.put(const HostEntry(id: 'h1', name: 'Database (newer here)', host: 'db2.example.com', username: 'ops'));
    final result = await importBackup(b, entries);
    expect((result.added, result.kept), (1, 1));
    expect(b.entry<HostEntry>('h1')!.name, 'Database (newer here)', reason: 'nothing here is overwritten');
    expect(b.entry<KeyEntry>('k1')!.privateKey, 'KEY-MATERIAL');
  });

  test('a file that is not a backup, or from a newer version, is refused', () async {
    final crypto = await VaultCrypto.load();
    for (final (text, problem) in [
      ('not json at all', BackupProblem.notABackup),
      ('{"format": "something-else"}', BackupProblem.notABackup),
      ('{"format": "tildeck-backup", "version": 99}', BackupProblem.newerVersion),
    ]) {
      await expectLater(
        readBackup(text, password, crypto),
        throwsA(isA<BackupException>().having((e) => e.problem, 'problem', problem)),
        reason: text,
      );
    }
    expect(backupFileName(DateTime(2026, 10, 2)), 'tildeck-backup-2026-10-02.json');
  });

  testWidgets('the backup panel saves with the master password and restores into the vault', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vault = (await tester.runAsync(() async {
      final v = await vaultNamed('a', password);
      await v.put(const HostEntry(id: 'h1', name: 'Database', host: 'db.example.com', username: 'ops'));
      return v;
    }))!;
    final files = FolderFiles(dir);
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
        home: Scaffold(
          body: BackupPanel(vault: vault, files: files, clock: () => DateTime(2026, 10, 2)),
        ),
      ),
    );
    Future<void> waitFor(bool Function() done) async {
      for (var i = 0; i < 2000 && !done(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        // Advances the test clock too, so a closed dialog finishes leaving.
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
    }

    // A wrong master password saves nothing.
    await tester.tap(find.byKey(const ValueKey('backupExport')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('backupPassword')), 'not-the-password-123');
    await tester.tap(find.byKey(const ValueKey('backupPasswordContinue')));
    await waitFor(() => find.byKey(const ValueKey('backupError')).evaluate().isNotEmpty);
    expect(files.last, isNull);

    await tester.tap(find.byKey(const ValueKey('backupExport')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('backupPassword')), password);
    await tester.tap(find.byKey(const ValueKey('backupPasswordContinue')));
    await waitFor(() => find.textContaining('Backup saved').evaluate().isNotEmpty);
    expect(files.last!.path, endsWith('tildeck-backup-2026-10-02.json'));

    // Deleted here, then restored from the backup.
    await tester.runAsync(() => vault.delete('h1'));
    await tester.tap(find.byKey(const ValueKey('backupImport')));
    await waitFor(() => find.byKey(const ValueKey('backupPassword')).evaluate().isNotEmpty);
    await tester.enterText(find.byKey(const ValueKey('backupPassword')), password);
    await tester.tap(find.byKey(const ValueKey('backupPasswordContinue')));
    await waitFor(
      () => vault.entry<HostEntry>('h1') != null || find.byKey(const ValueKey('backupError')).evaluate().isNotEmpty,
    );
    expect(find.byKey(const ValueKey('backupError')), findsNothing);
    expect(vault.entry<HostEntry>('h1')?.name, 'Database');
  });
}
