import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/settings/device_settings.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';
import 'package:tildeck/terminal/session_log.dart';

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
  test('a log keeps the text, without colors, cursor moves, titles, or controls', () {
    expect(
      SessionLog.plainText('\x1b]0;web: ~\x07\x1b[1;32mops@web\x1b[0m:~\$ ls\r\n\x1b[2Kfile\x07.txt\r\n\x1b(B'),
      'ops@web:~\$ ls\nfile.txt\n',
    );
  });

  test('logs are off by default and kept in the settings', () {
    expect(const DeviceSettings().sessionLogs, isFalse);
    final on = const DeviceSettings().copyWith(sessionLogs: true);
    expect(DeviceSettings.fromJson(on.toJson()), on);
  });

  test("a session's output goes to its log file, named by time and target", () async {
    final dir = await Directory.systemTemp.createTemp('tildeck-logs');
    addTearDown(() => dir.delete(recursive: true));
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    Socket? device;
    server.listen((s) => device = s);
    final target = ConnectionTarget(
      host: '127.0.0.1',
      port: server.port,
      username: '',
      protocol: ConnectionProtocol.telnet,
    );
    final session = TerminalSession(target);
    session.log = await SessionLog.open(dir, target.label, DateTime(2026, 10, 2, 9, 5, 7));
    final file = session.log!.file;
    unawaited(session.start(SshConnector(knownHosts: MemoryKnownHosts()), _trust));
    await _until(() => session.state == SessionState.connected && device != null);
    device!.add('\x1b[31mrouter>\x1b[0m show ver\r\nIOS 15\r\n'.codeUnits);
    await _until(() => session.terminal.buffer.getText().contains('IOS 15'));
    session.disconnect();
    await server.close();
    await _until(() => file.existsSync() && file.readAsStringSync().contains('IOS 15'));

    expect(file.uri.pathSegments.last, '2026-10-02 09-05-07 127.0.0.1_${server.port}.log');
    expect(file.readAsStringSync(), 'router> show ver\nIOS 15\n');
  });
}
