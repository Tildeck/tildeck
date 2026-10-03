import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';

/// A Telnet server that keeps what it is sent.
class Device {
  late final ServerSocket server;
  final received = BytesBuilder();
  Socket? client;

  Future<void> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) {
      client = s;
      s.listen(received.add);
    });
  }

  String get text => latin1.decode(received.toBytes());
}

Future<bool> _trust({
  required ConnectionTarget target,
  required KnownHost presented,
  required HostKeyStatus status,
  KnownHost? previous,
}) async => true;

Future<void> _until(bool Function() condition, [String what = '']) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue, reason: what);
}

void main() {
  test('typing reaches the other session; replies to the program and app input do not', () async {
    final a = Device();
    final b = Device();
    await a.start();
    await b.start();
    final connector = SshConnector(knownHosts: MemoryKnownHosts());
    TerminalSession open(Device d) => TerminalSession(
      ConnectionTarget(
        host: '127.0.0.1',
        port: d.server.port,
        username: '',
        password: 'secret',
        protocol: ConnectionProtocol.telnet,
      ),
    );
    final one = open(a);
    final two = open(b);
    addTearDown(() {
      one.disconnect();
      two.disconnect();
      a.server.close();
      b.server.close();
    });
    unawaited(one.start(connector, _trust));
    unawaited(two.start(connector, _trust));
    await _until(() => one.state == SessionState.connected && two.state == SessionState.connected, 'connected');
    one.onTyped = two.receive;

    one.terminal.textInput('uptime\r');
    await _until(() => b.text.contains('uptime\r'), 'broadcast');

    // The program asks the terminal where its cursor is: the answer is for
    // that program only.
    a.client!.add(utf8.encode('\x1b[6n'));
    await _until(() => RegExp(r'\x1b\[\d+;\d+R').hasMatch(a.text), 'cursor report');
    one.terminal.write('Password: ');
    one.atPasswordPrompt = true;
    one.fillPassword();
    one.run('ls');
    await _until(() => a.text.contains('ls\r'), 'snippet');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(b.text, isNot(contains('\x1b[')), reason: 'no cursor report');
    expect(b.text, isNot(contains('secret')), reason: 'no saved password');
    expect(b.text, isNot(contains('ls')), reason: 'no snippet');

    one.onTyped = null;
    one.terminal.textInput('w');
    await _until(() => a.text.endsWith('w'));
    expect(b.text, isNot(endsWith('w')), reason: 'off again');
  });
}
