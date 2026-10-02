import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';
import 'package:tildeck/ui/hosts_page.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

Future<bool> _trust({
  required ConnectionTarget target,
  required KnownHost presented,
  required HostKeyStatus status,
  KnownHost? previous,
}) async => true;

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

void main() {
  test('a host keeps its terminal type and charset, and the connection takes them', () async {
    const host = HostEntry(
      id: 'h',
      name: 'Old switch',
      host: '10.0.0.2',
      username: 'admin',
      password: 'pw',
      terminalType: 'vt100',
      charset: TerminalCharset.latin1,
    );
    final back = HostEntry.fromJson('h', host.dataJson());
    expect((back.terminalType, back.charset), ('vt100', TerminalCharset.latin1));
    final older = HostEntry.fromJson(
      'h',
      {...host.dataJson()}
        ..remove('terminal_type')
        ..remove('charset'),
    );
    expect((older.terminalType, older.charset), (null, TerminalCharset.utf8), reason: 'records from before');
  });

  testWidgets('connecting passes them on', (tester) async {
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-tt')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      await v.put(const HostEntry(id: 'a', name: 'A', host: 'a', username: 'u', password: 'pw', terminalType: 'vt220'));
      await v.put(const HostEntry(id: 'b', name: 'B', host: 'b', username: 'u', password: 'pw'));
      return v;
    }))!;
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
    final a = (await tester.runAsync(() => connectionTargetFor(context, vault, vault.entry<HostEntry>('a')!)))!;
    final b = (await tester.runAsync(() => connectionTargetFor(context, vault, vault.entry<HostEntry>('b')!)))!;
    expect((a.terminalType, b.terminalType, b.charset), ('vt220', 'xterm-256color', TerminalCharset.utf8));
  });

  test('a Latin-1 session reads and writes Latin-1, and announces its terminal type', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = <int>[];
    Socket? device;
    server.listen((s) {
      device = s;
      s.listen(received.addAll);
    });
    final session = TerminalSession(
      ConnectionTarget(
        host: '127.0.0.1',
        port: server.port,
        username: '',
        protocol: ConnectionProtocol.telnet,
        terminalType: 'vt100',
        charset: TerminalCharset.latin1,
      ),
    );
    addTearDown(() {
      session.disconnect();
      server.close();
    });
    unawaited(session.start(SshConnector(knownHosts: MemoryKnownHosts()), _trust));
    await _until(() => session.state == SessionState.connected && device != null);

    // "Café" in Latin-1: é is the single byte 0xE9.
    device!.add([0x43, 0x61, 0x66, 0xe9]);
    await _until(() => session.terminal.buffer.lines[0].getText().startsWith('Café'));
    session.terminal.textInput('é€');
    await _until(() => received.length >= 2 && received.sublist(received.length - 2).join(',') == '233,63');

    // The server asks for the terminal type (IAC SB TTYPE SEND IAC SE).
    received.clear();
    device!.add([255, 250, 24, 1, 255, 240]);
    await _until(() => String.fromCharCodes(received).contains('VT100'));
  });
}
