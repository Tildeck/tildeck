import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tildeck/server_check.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

MockClient server({Object? info, int infoStatus = 200, Object? ready, int readyStatus = 200}) {
  return MockClient((request) async {
    switch (request.url.path) {
      case '/api/info':
        return json(info ?? {'name': 'tildeck', 'version': '0.0.0', 'protocol_version': kProtocolVersion}, infoStatus);
      case '/api/health/ready':
        return json(ready ?? {'status': 'ok', 'database': 'ok', 'error': null}, readyStatus);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  test('a matching server with a database is ready', () async {
    final result = await ServerChecker(client: server()).check('https://sync.example.com/');
    expect(result, isA<ServerReady>());
    expect((result as ServerReady).info.version, '0.0.0');
  });

  test('an address that is not absolute http(s) is rejected before any request', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('', 200);
    });
    for (final input in ['sync.example.com', 'ftp://sync.example.com', '', '   ']) {
      final result = await ServerChecker(client: client).check(input);
      expect((result as ServerFailed).problem, ServerProblem.invalidAddress, reason: input);
    }
    expect(requests, 0);
  });

  test('a server speaking another protocol version cannot sync', () async {
    final checker = ServerChecker(
      client: server(info: {'name': 'tildeck', 'version': '9.0.0', 'protocol_version': kProtocolVersion + 1}),
    );
    final result = await checker.check('https://sync.example.com');
    expect((result as ServerFailed).problem, ServerProblem.unsupportedProtocol);
  });

  test('a database outage is reported from the readiness error code', () async {
    final checker = ServerChecker(
      client: server(
        ready: {'status': 'error', 'database': 'error', 'error': 'database_unavailable'},
        readyStatus: 503,
      ),
    );
    final result = await checker.check('https://sync.example.com');
    expect((result as ServerFailed).problem, ServerProblem.databaseUnavailable);
  });

  test('something that is not a Tildeck server is named as such', () async {
    final html = MockClient((_) async => http.Response('<html>hello</html>', 200));
    expect(
      ((await ServerChecker(client: html).check('https://example.com')) as ServerFailed).problem,
      ServerProblem.notTildeck,
    );

    final missing = MockClient((_) async => http.Response('nope', 404));
    expect(
      ((await ServerChecker(client: missing).check('https://example.com')) as ServerFailed).problem,
      ServerProblem.notTildeck,
    );
  });

  test('no answer at all is unreachable', () async {
    final down = MockClient((_) async => throw http.ClientException('connection refused'));
    final result = await ServerChecker(client: down).check('https://sync.example.com');
    expect((result as ServerFailed).problem, ServerProblem.unreachable);
  });
}
