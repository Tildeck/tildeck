import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/serial.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/hosts_page.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

/// A serial line in memory: what the device sends, and what was typed.
class FakeLine {
  final device = StreamController<Uint8List>();
  final typed = <int>[];
  final done = Completer<void>();
  String? port;
  int? baudRate;

  SerialLine open(String port, int baudRate) {
    this.port = port;
    this.baudRate = baudRate;
    return SerialLine(
      output: device.stream,
      write: typed.addAll,
      done: done.future,
      close: () {
        if (!done.isCompleted) done.complete();
      },
    );
  }
}

Future<bool> _noPrompt({
  required ConnectionTarget target,
  required KnownHost presented,
  required HostKeyStatus status,
  KnownHost? previous,
}) async => false;

/// Real file work finishes outside the fake clock.
Future<void> waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 1000 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

void main() {
  const target = ConnectionTarget(host: 'COM3', port: 9600, username: '', protocol: ConnectionProtocol.serial);
  final connector = SshConnector(knownHosts: MemoryKnownHosts());

  test('a serial session opens the port at its baud rate, shows what arrives and sends what is typed', () async {
    final line = FakeLine();
    final session = TerminalSession(target, openSerial: line.open);
    final started = session.start(connector, _noPrompt);
    await Future<void>.delayed(Duration.zero);
    expect((line.port, line.baudRate), ('COM3', 9600));
    expect(session.state, SessionState.connected);
    expect(session.isSsh, isFalse, reason: 'no files or server history over a serial line');

    line.device.add(utf8.encode('router> '));
    await Future<void>.delayed(Duration.zero);
    expect(session.terminal.buffer.lines[0].getText(), startsWith('router> '));
    session.terminal.textInput('show ver\r');
    expect(utf8.decode(line.typed), 'show ver\r');

    session.disconnect();
    await started;
    expect(session.state, SessionState.closed);
    expect(session.problem, isNull, reason: 'closed on purpose is not a drop');
  });

  test('a device that goes away is a drop, and a port that will not open says so', () async {
    final line = FakeLine();
    final session = TerminalSession(target, openSerial: line.open);
    final started = session.start(connector, _noPrompt);
    await Future<void>.delayed(Duration.zero);
    line.done.complete();
    await started;
    expect(session.problem, ConnectProblem.disconnected);

    final failing = TerminalSession(
      target,
      openSerial: (_, _) => throw const ConnectException(ConnectProblem.serialFailed),
    );
    await failing.start(connector, _noPrompt);
    expect(failing.problem, ConnectProblem.serialFailed);
  });

  test('a serial host is named by its port, and its baud rate when not the usual', () {
    const host = HostEntry(
      id: 'h',
      name: 'Switch',
      host: 'COM3',
      port: 115200,
      username: '',
      protocol: ConnectionProtocol.serial,
    );
    expect(host.label, 'COM3');
    expect(target.label, 'COM3 9600');
    expect(host.isSsh, isFalse);
    expect(defaultPortOf(ConnectionProtocol.serial), defaultBaudRate);
  });

  testWidgets('the host editor makes a serial host: a port and a baud rate, no sign-in or jump host', (tester) async {
    serialSupported = true;
    addTearDown(() => serialSupported = Platform.isWindows);
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-serial')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      await v.put(const HostEntry(id: 'j', name: 'Bastion', host: 'bastion.example.com', username: 'ops'));
      await v.put(const GroupEntry(id: 'g', name: 'Lab', jumpHostId: 'j'));
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
        home: HostEditorPage(vault: vault),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('hostName')), 'Switch');
    await tester.enterText(find.byKey(const ValueKey('hostGroup')), 'Lab');
    await tester.tap(find.text('Serial'));
    await tester.pumpAndSettle();
    expect(find.text('Serial port'), findsOneWidget);
    expect(find.text('Baud rate'), findsOneWidget);
    final port = tester.widget<TextFormField>(find.byKey(const ValueKey('port')));
    expect(port.controller!.text, '115200', reason: 'the default port moves to the usual baud rate');
    for (final key in ['username', 'hostIdentity', 'jumpHost', 'agentForwarding', 'hostEnv', 'startupSnippet']) {
      expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
    }
    expect(find.byKey(const ValueKey('serialPorts')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('host')), 'COM3');
    await tester.ensureVisible(find.byKey(const ValueKey('saveHost')));
    await tester.tap(find.byKey(const ValueKey('saveHost')));
    await waitFor(tester, () => vault.hosts.length == 2);
    final host = vault.hosts.firstWhere((h) => h.name == 'Switch');
    expect((host.protocol, host.host, host.port, host.username), (ConnectionProtocol.serial, 'COM3', 115200, ''));
    expect(jumpChainOf(vault, host), isEmpty, reason: "the group's jump host is not for a local port");
    expect(jumpCandidatesFor(vault, 'j'), isEmpty, reason: 'a serial host is no jump host');

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final connect = (await tester.runAsync(() => connectionTargetFor(context, vault, host)))!;
    expect(
      (connect.protocol, connect.host, connect.port, connect.jump),
      (ConnectionProtocol.serial, 'COM3', 115200, null),
    );
  });
}
