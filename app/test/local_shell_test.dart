import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/local/local_shell.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/hosts_page.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

void main() {
  group('shells on Windows', () {
    List<LocalShell> find(Map<String, String> env, Set<String> files) =>
        findLocalShells(windows: true, environment: env, exists: files.contains);

    test('PowerShell 7 from PATH first, then Windows PowerShell, Command Prompt, and WSL', () {
      final shells = find(
        {
          'SystemRoot': r'C:\Windows',
          'Path': r'C:\Tools;C:\Program Files\PowerShell\7\',
          'ComSpec': r'C:\Windows\system32\cmd.exe',
        },
        {
          r'C:\Program Files\PowerShell\7\pwsh.exe',
          r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
          r'C:\Windows\system32\cmd.exe',
          r'C:\Windows\System32\wsl.exe',
        },
      );
      expect(shells.map((s) => s.kind), [
        LocalShellKind.pwsh,
        LocalShellKind.windowsPowerShell,
        LocalShellKind.cmd,
        LocalShellKind.wsl,
      ]);
      expect(shells.first.executable, r'C:\Program Files\PowerShell\7\pwsh.exe');
      expect(shells[2].executable, r'C:\Windows\system32\cmd.exe', reason: 'ComSpec, in any letter case');
    });

    test('PowerShell 7 outside PATH is found where it installs; what is missing is left out', () {
      final shells = find(
        {'SYSTEMROOT': r'D:\Win', 'ProgramFiles': r'D:\Programs'},
        {r'D:\Programs\PowerShell\7\pwsh.exe', r'D:\Win\System32\cmd.exe'},
      );
      expect(shells.map((s) => s.executable), [r'D:\Programs\PowerShell\7\pwsh.exe', r'D:\Win\System32\cmd.exe']);
    });
  });

  test('elsewhere, the login shell, or sh', () {
    final bash = findLocalShells(windows: false, environment: {'SHELL': '/bin/zsh'}, exists: (p) => p == '/bin/zsh');
    expect(bash.single.executable, '/bin/zsh');
    expect(bash.single.arguments, ['-l']);
    expect(findLocalShells(windows: false, environment: const {}, exists: (_) => false).single.executable, '/bin/sh');
  });

  testWidgets('the hosts screen opens a local terminal with the chosen shell', (tester) async {
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-local')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      return v;
    }))!;
    Widget page(List<LocalShell>? shells, void Function(ConnectionTarget) onConnect) => MaterialApp(
      theme: buildTheme(Brightness.light),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: HostsPage(vault: vault, onConnect: onConnect, localShells: shells),
      ),
    );

    // On a phone there is no local terminal.
    await tester.pumpWidget(page(null, (_) {}));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('openLocalTerminal')), findsNothing);

    ConnectionTarget? opened;
    await tester.pumpWidget(
      page(const [
        LocalShell(LocalShellKind.windowsPowerShell, r'C:\ps.exe'),
        LocalShell(LocalShellKind.cmd, r'C:\cmd.exe'),
      ], (t) => opened = t),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('openLocalTerminal')));
    await tester.pumpAndSettle();
    expect(find.text('Windows PowerShell'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('localShell-cmd')));
    await tester.pumpAndSettle();
    expect(opened?.protocol, ConnectionProtocol.local);
    expect(opened?.localShell?.executable, r'C:\cmd.exe');
    expect(opened?.label, 'Command Prompt');
  });
}
