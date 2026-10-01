import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/proxy.dart';

import 'fake_proxies.dart';

/// A service that greets first, as an SSH server does.
Future<ServerSocket> greeter() async {
  final server = await ServerSocket.bind('127.0.0.1', 0);
  server.listen((s) {
    s.write('SSH-2.0-greeting\r\n');
    s.listen((data) => s.add(data)); // and echoes
  });
  return server;
}

Future<String> roundTrip(ProxyConfig proxy, int port) async {
  final socket = await connectThroughProxy(proxy, '127.0.0.1', port);
  final received = StringBuffer();
  final sub = socket.stream.listen((d) => received.write(utf8.decode(d)));
  socket.sink.add(utf8.encode('ping'));
  for (var i = 0; i < 100 && !received.toString().contains('ping'); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await sub.cancel();
  socket.destroy();
  return received.toString();
}

void main() {
  late ServerSocket target;
  setUp(() async => target = await greeter());
  tearDown(() => target.close());

  for (final kind in ProxyKind.values) {
    group(kind.name, () {
      Future<FakeProxy> start({String? username, String? password}) => kind == ProxyKind.socks5
          ? FakeProxy.socks5(username: username, password: password)
          : FakeProxy.http(username: username, password: password);

      test('relays both ways, including what the target says first', () async {
        final proxy = await start();
        addTearDown(proxy.close);
        final text = await roundTrip(ProxyConfig(kind: kind, host: '127.0.0.1', port: proxy.port), target.port);
        expect(text, 'SSH-2.0-greeting\r\nping');
        expect(proxy.targets, ['127.0.0.1:${target.port}']);
      });

      test('signs in to the proxy', () async {
        final proxy = await start(username: 'ops', password: 's3cret');
        addTearDown(proxy.close);
        final config = ProxyConfig(
          kind: kind,
          host: '127.0.0.1',
          port: proxy.port,
          username: 'ops',
          password: 's3cret',
        );
        expect(await roundTrip(config, target.port), contains('ping'));
      });

      test('a wrong or missing password is reported as such', () async {
        final proxy = await start(username: 'ops', password: 's3cret');
        addTearDown(proxy.close);
        for (final config in [
          ProxyConfig(kind: kind, host: '127.0.0.1', port: proxy.port, username: 'ops', password: 'nope'),
          ProxyConfig(kind: kind, host: '127.0.0.1', port: proxy.port),
        ]) {
          await expectLater(
            connectThroughProxy(config, '127.0.0.1', target.port),
            throwsA(isA<ProxyException>().having((e) => e.problem, 'problem', ProxyProblem.authFailed)),
          );
        }
      });

      test('a target the proxy cannot reach is the target failing, not the proxy', () async {
        final proxy = await start();
        addTearDown(proxy.close);
        await expectLater(
          connectThroughProxy(ProxyConfig(kind: kind, host: '127.0.0.1', port: proxy.port), '127.0.0.1', 1),
          throwsA(isA<ProxyException>().having((e) => e.problem, 'problem', ProxyProblem.targetFailed)),
        );
      });
    });
  }

  test('a proxy that is not there is unreachable', () async {
    final free = await ServerSocket.bind('127.0.0.1', 0);
    final port = free.port;
    await free.close();
    await expectLater(
      connectThroughProxy(ProxyConfig(kind: ProxyKind.socks5, host: '127.0.0.1', port: port), '127.0.0.1', 22),
      throwsA(isA<ProxyException>().having((e) => e.problem, 'problem', ProxyProblem.unreachable)),
    );
  });
}
