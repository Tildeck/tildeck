import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/host_os.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/host_avatar.dart';
import 'package:tildeck/ui/hosts_page.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

void main() {
  group('parseOs', () {
    test('reads the distribution from os-release', () {
      expect(parseOs('PRETTY_NAME="Ubuntu 24.04.1 LTS"\nNAME="Ubuntu"\nID=ubuntu\nID_LIKE=debian\n'), HostOs.ubuntu);
      expect(parseOs('NAME="Rocky Linux"\nID="rocky"\nID_LIKE="rhel centos fedora"\n'), HostOs.rocky);
      expect(parseOs("ID='alpine'\nVERSION_ID=3.20.3\n"), HostOs.alpine);
      expect(parseOs('ID=opensuse-leap\nID_LIKE="suse opensuse"\n'), HostOs.opensuse);
      expect(parseOs('ID=rhel\n'), HostOs.redhat);
      expect(parseOs('ID=raspbian\nID_LIKE=debian\n'), HostOs.debian);
    });

    test('falls back to the nearest system it is like, else plain Linux', () {
      expect(parseOs('ID=linuxmint\nID_LIKE="ubuntu debian"\n'), HostOs.mint);
      expect(parseOs('ID=neon\nID_LIKE="ubuntu debian"\n'), HostOs.ubuntu);
      expect(parseOs('ID=amzn\nID_LIKE="centos rhel fedora"\n'), HostOs.centos);
      expect(parseOs('ID=somethingnew\n'), HostOs.linux);
    });

    test('reads the kernel name where there is no os-release', () {
      expect(parseOs('Darwin\n'), HostOs.macos);
      expect(parseOs('OpenBSD\n'), HostOs.openbsd);
      expect(parseOs('Linux\n'), HostOs.linux);
    });

    test("recognises Windows' cmd", () {
      expect(parseOs('\r\nMicrosoft Windows [Version 10.0.20348.2700]\r\n'), HostOs.windows);
    });

    test('knows nothing from an empty or foreign answer', () {
      expect(parseOs(''), isNull);
      expect(parseOs('% Invalid input detected at \'^\' marker.\n'), isNull);
    });
  });

  test('a host keeps its system and colour, and an unknown name reads as none', () {
    const host = HostEntry(
      id: 'h',
      name: 'Web',
      host: 'web.example.com',
      username: 'ops',
      os: HostOs.fedora,
      tint: HostTint.blue,
    );
    final back = HostEntry.fromJson('h', host.dataJson());
    expect(back.os, HostOs.fedora);
    expect(back.tint, HostTint.blue);

    final older = HostEntry.fromJson('h', {...host.dataJson(), 'os': 'beos', 'tint': 'purple'});
    expect(older.os, isNull);
    expect(older.tint, isNull);
    final before = HostEntry.fromJson(
      'h',
      {...host.dataJson()}
        ..remove('os')
        ..remove('tint'),
    );
    expect(before.os, isNull);
    expect(before.tint, isNull);
  });

  testWidgets('the editor gives a host a colour, and can hand its system back to detection', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-os')))!;
    addTearDown(() => dir.delete(recursive: true));
    const detected = HostEntry(id: 'h', name: 'Web', host: 'web.example.com', username: 'ops', os: HostOs.ubuntu);
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      await v.put(detected);
      return v;
    }))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: HostEditorPage(vault: vault, host: detected),
      ),
    );
    await tester.pumpAndSettle();
    HostAvatar preview() => tester.widget<HostAvatar>(find.byKey(const ValueKey('hostLookPreview')));
    expect((preview().os, preview().tint), (HostOs.ubuntu, null));

    await tester.tap(find.byKey(const ValueKey('tint-blue')));
    await tester.pumpAndSettle();
    expect(preview().tint, HostTint.blue);
    await tester.tap(find.byKey(const ValueKey('hostOs')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detect on the next connection').last);
    await tester.pumpAndSettle();
    expect(preview().os, isNull);

    await tester.ensureVisible(find.byKey(const ValueKey('saveHost')));
    await tester.tap(find.byKey(const ValueKey('saveHost')));
    for (var i = 0; i < 200 && vault.entry<HostEntry>('h')?.tint == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    final saved = vault.entry<HostEntry>('h')!;
    expect((saved.tint, saved.os), (HostTint.blue, null));
  });
}
