// SSH through proxies, against the throwaway OpenSSH server of
// scripts/verify.sh --area app (see ssh_integration_test.dart for the
// environment). Skipped without it, unless TILDECK_REQUIRE_SSH_TESTS is set.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/proxy.dart';
import 'package:tildeck/ssh/ssh_connector.dart';

import 'fake_proxies.dart';

final env = Platform.environment;
final host = env['TILDECK_TEST_SSH_HOST'];
final port = int.tryParse(env['TILDECK_TEST_SSH_PORT'] ?? '') ?? 2222;
final user = env['TILDECK_TEST_SSH_USER'] ?? 'tildeck';
final password = env['TILDECK_TEST_SSH_PASSWORD'];

Future<bool> trust({
  required ConnectionTarget target,
  required KnownHost presented,
  required HostKeyStatus status,
  KnownHost? previous,
}) async => true;

void main() {
  final skip = host == null
      ? (env['TILDECK_REQUIRE_SSH_TESTS'] == null ? 'no test SSH server in the environment' : null)
      : null;

  group('proxies', skip: skip, () {
    setUpAll(() {
      if (host == null) fail('TILDECK_REQUIRE_SSH_TESTS is set but no test SSH server was provided.');
    });

    ConnectionTarget through(ProxyConfig proxy) =>
        ConnectionTarget(host: host!, port: port, username: user, password: password, proxy: proxy);

    for (final kind in ProxyKind.values) {
      test('an SSH session through a ${kind.name} proxy that asks for a password', () async {
        final proxy = kind == ProxyKind.socks5
            ? await FakeProxy.socks5(username: 'ops', password: 's3cret')
            : await FakeProxy.http(username: 'ops', password: 's3cret');
        addTearDown(proxy.close);
        final config = ProxyConfig(
          kind: kind,
          host: '127.0.0.1',
          port: proxy.port,
          username: 'ops',
          password: 's3cret',
        );
        final client = await SshConnector(
          knownHosts: MemoryKnownHosts(),
        ).connect(through(config), promptHostKey: trust);
        addTearDown(client.close);
        expect(utf8.decode(await client.run('echo via-proxy')).trim(), 'via-proxy');
        expect(proxy.targets, ['$host:$port'], reason: 'the proxy resolved the name');
      });
    }

    test('a refused proxy password is reported at the proxy', () async {
      final proxy = await FakeProxy.http(username: 'ops', password: 's3cret');
      addTearDown(proxy.close);
      final config = ProxyConfig(kind: ProxyKind.http, host: '127.0.0.1', port: proxy.port, username: 'ops');
      await expectLater(
        SshConnector(knownHosts: MemoryKnownHosts()).connect(through(config), promptHostKey: trust),
        throwsA(
          isA<ConnectException>()
              .having((e) => e.problem, 'problem', ConnectProblem.authFailed)
              .having((e) => e.via, 'via', config.label),
        ),
      );
    });

    test('through a jump host, the proxy is used for the first hop only', () async {
      final proxy = await FakeProxy.socks5();
      addTearDown(proxy.close);
      final config = ProxyConfig(kind: ProxyKind.socks5, host: '127.0.0.1', port: proxy.port);
      final target = ConnectionTarget(
        host: '127.0.0.1',
        port: 2222,
        username: user,
        password: password,
        proxy: config,
        jump: through(config),
      );
      final client = await SshConnector(knownHosts: MemoryKnownHosts()).connect(target, promptHostKey: trust);
      addTearDown(client.close);
      expect(utf8.decode(await client.run('echo hopped')).trim(), 'hopped');
      expect(proxy.targets, ['$host:$port'], reason: 'not 127.0.0.1:2222, which only the jump host can reach');
    });
  });
}
