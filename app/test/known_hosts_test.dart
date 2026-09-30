import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';

const keyA = KnownHost(type: 'ssh-ed25519', fingerprint: 'SHA256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
const keyB = KnownHost(type: 'ssh-ed25519', fingerprint: 'SHA256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');

void main() {
  test('a host is unknown, then trusted, and a different key is a change', () async {
    final store = KnownHostsStore.memory();
    expect(await store.check('example.com', 22, keyA), HostKeyStatus.unknown);
    await store.trust('example.com', 22, keyA);
    expect(await store.check('example.com', 22, keyA), HostKeyStatus.trusted);
    expect(await store.check('example.com', 22, keyB), HostKeyStatus.changed);
    // The same host name in another case is the same host; another port is not.
    expect(await store.check('EXAMPLE.com', 22, keyA), HostKeyStatus.trusted);
    expect(await store.check('example.com', 2222, keyA), HostKeyStatus.unknown);
  });

  test('trusted keys survive a restart, and replacing a key replaces it', () async {
    final dir = await Directory.systemTemp.createTemp('tildeck-known-hosts');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/known_hosts.json');

    await KnownHostsStore(() async => file).trust('example.com', 22, keyA);
    final reopened = KnownHostsStore(() async => file);
    expect(await reopened.check('example.com', 22, keyA), HostKeyStatus.trusted);

    await reopened.trust('example.com', 22, keyB);
    expect(await KnownHostsStore(() async => file).check('example.com', 22, keyB), HostKeyStatus.trusted);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  test('Ctrl from the key bar turns the next letter into its control code', () {
    final session = TerminalSession(const ConnectionTarget(host: 'h', username: 'u'));
    expect(session.applyCtrl('c'), 'c');
    session.toggleCtrl();
    expect(session.applyCtrl('c'), '\x03');
    expect(session.ctrlLatched, isFalse, reason: 'the latch applies to one character');
    session.toggleCtrl();
    expect(session.applyCtrl('D'), '\x04');
    session.toggleCtrl();
    expect(session.applyCtrl('1'), '1', reason: 'digits have no control code');
    session.dispose();
  });
}
