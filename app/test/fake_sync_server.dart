import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The server's account and sync API (server/app/routers/account.py and
/// sync.py), in memory, for tests of the client: exactly-next versions,
/// account revisions, conflicts with the current record, tombstones,
/// paging, and new devices that wait for approval. Kept small on purpose;
/// the server's own behavior is covered by server/tests against PostgreSQL,
/// and this must follow it when that changes.
class FakeSyncServer {
  FakeSyncServer({this.pullLimit = 1000});

  int pullLimit;
  int revision = 0;
  final records = <String, Map<String, dynamic>>{};

  /// Valid device tokens.
  final tokens = <String>{'token-a', 'token-b'};

  /// Refuse sync with this error code (403 `email_not_verified`, say).
  String? refuse;

  /// Runs inside a push, before the server answers.
  Future<void> Function()? duringPush;

  int pushes = 0;

  /// The one account, once registered: its request body.
  Map<String, dynamic>? account;
  bool emailVerified = true;

  /// id -> {id, name, status, token, claim}.
  final devices = <String, Map<String, dynamic>>{};

  http.Client get client => MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    if (path == '/api/info') {
      return _json({'name': 'tildeck', 'version': '0.0.0', 'protocol_version': 1});
    }
    if (path == '/api/health/ready') return _json({'status': 'ok', 'database': 'ok', 'error': null});
    if (request.headers['Tildeck-Protocol'] != '1') return _error(400, 'unsupported_protocol');
    final body = request.body.isEmpty ? const <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;

    switch ((request.method, path)) {
      case ('POST', '/api/account/prelogin'):
        return _json({'kdf': account?['kdf'] ?? _kdf});
      case ('POST', '/api/account/register'):
        account = body;
        final device = body['device'] as Map<String, dynamic>;
        return _json(_signedIn(_addDevice(device['id'] as String, device['name'] as String, 'active')));
      case ('POST', '/api/account/signin'):
        return _signin(body);
      case ('POST', '/api/devices/claim'):
        return _claim(body);
      case ('POST', '/api/account/recovery/start'):
        if (!_recoveryOk(body)) return _error(401, 'recovery_failed');
        return _json({'vault_id': account!['vault_id'], 'wrap_rk': account!['wrap_rk']});
      case ('POST', '/api/account/recovery/complete'):
        if (!_recoveryOk(body)) return _error(401, 'recovery_failed');
        _setPassword(body['new'] as Map<String, dynamic>);
        _revokeOthers(null);
        final device = body['device'] as Map<String, dynamic>;
        return _json(_signedIn(_addDevice(device['id'] as String, device['name'] as String, 'active')));
    }

    final token = (request.headers['authorization'] ?? '').replaceFirst('Bearer ', '');
    if (!tokens.contains(token)) return _error(401, 'unauthorized');
    final caller = devices.values.where((d) => d['token'] == token).firstOrNull;

    if (request.method == 'GET' && path == '/api/account') {
      return _json({
        'email': account?['email'] ?? 'user@example.test',
        'email_verified': emailVerified,
        'locale': 'en',
        'devices': [
          for (final d in devices.values)
            {
              'id': d['id'],
              'name': d['name'],
              'status': d['status'],
              'created_at': '2026-09-30T09:00:00Z',
              'last_seen_at': d['status'] == 'active' ? '2026-09-30T11:30:00Z' : null,
              'current': identical(d, caller),
            },
        ],
      });
    }
    if (request.method == 'POST' && path == '/api/account/password') {
      if (body['auth_key'] != account!['auth_key']) return _error(401, 'invalid_credentials');
      _setPassword(body['new'] as Map<String, dynamic>);
      if (body['keep_other_devices'] != true) _revokeOthers(caller);
      passwordChanges++;
      return http.Response('', 204);
    }
    final action = RegExp(r'^/api/devices/([^/]+)/(approve|revoke)$').firstMatch(path);
    if (request.method == 'POST' && action != null) {
      final device = devices[action[1]];
      if (device == null) return _error(404, 'device_not_found');
      if (action[2] == 'approve') {
        device['status'] = 'active';
      } else {
        device['status'] = 'revoked';
        tokens.remove(device['token']);
      }
      return http.Response('', 204);
    }

    if (refuse != null) return _error(403, refuse!);
    if (path != '/api/sync/records') return _error(404, 'not_found');
    if (request.method == 'GET') return _pull(int.parse(request.url.queryParameters['since'] ?? '0'));
    return _push(body);
  }

  int passwordChanges = 0;

  bool _recoveryOk(Map<String, dynamic> body) =>
      account != null &&
      body['email'] == account!['email'] &&
      body['recovery_auth_key'] == account!['recovery_auth_key'];

  void _setPassword(Map<String, dynamic> next) {
    account!
      ..['kdf'] = next['kdf']
      ..['auth_key'] = next['auth_key']
      ..['wrap_pw'] = next['wrap_pw'];
  }

  void _revokeOthers(Map<String, dynamic>? keep) {
    for (final d in devices.values) {
      if (identical(d, keep) || d['status'] == 'revoked') continue;
      d['status'] = 'revoked';
      tokens.remove(d['token']);
    }
  }

  static const _kdf = {'alg': 'argon2id13', 'ops': 3, 'mem': 67108864, 'salt': 'AAAAAAAAAAAAAAAAAAAAAA=='};

  Map<String, dynamic> _addDevice(String id, String name, String status) {
    final device = <String, dynamic>{
      'id': id,
      'name': name,
      'status': status,
      'token': 'token-${devices.length + 1}-$id',
      'claim': 'claim-$id',
    };
    if (status == 'active') tokens.add(device['token'] as String);
    return devices[id] = device;
  }

  Map<String, Object?> _signedIn(Map<String, dynamic> device) {
    tokens.add(device['token'] as String);
    return {
      'device_token': device['token'],
      'email_verified': emailVerified,
      'vault': {'vault_id': account!['vault_id'], 'kdf': account!['kdf'], 'wrap_pw': account!['wrap_pw']},
    };
  }

  http.Response _signin(Map<String, dynamic> body) {
    if (account == null || body['email'] != account!['email'] || body['auth_key'] != account!['auth_key']) {
      return _error(401, 'invalid_credentials');
    }
    final info = body['device'] as Map<String, dynamic>;
    final known = devices[info['id']];
    if (known != null && known['status'] == 'revoked') return _error(409, 'device_revoked');
    if (known != null && known['status'] == 'active') {
      return _json({'status': 'active', 'signed_in': _signedIn(known)});
    }
    final device = _addDevice(info['id'] as String, info['name'] as String, 'pending');
    return http.Response(
      jsonEncode({
        'status': 'pending',
        'device_id': device['id'],
        'claim_token': device['claim'],
        'email_approval': true,
      }),
      202,
      headers: {'content-type': 'application/json'},
    );
  }

  http.Response _claim(Map<String, dynamic> body) {
    final device = devices[body['device_id']];
    if (device == null || device['claim'] == null || device['claim'] != body['claim_token']) {
      return _error(401, 'invalid_token');
    }
    if (device['status'] == 'pending') return _error(409, 'device_pending');
    if (device['status'] != 'active') return _error(409, 'device_revoked');
    device['claim'] = null;
    return _json(_signedIn(device));
  }

  http.Response _error(int status, String code) =>
      http.Response(jsonEncode({'error': code}), status, headers: {'content-type': 'application/json'});

  http.Response _json(Object body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

  http.Response _pull(int since) {
    final newer = records.values.where((r) => (r['revision'] as int) > since).toList()
      ..sort((a, b) => (a['revision'] as int).compareTo(b['revision'] as int));
    final page = newer.take(pullLimit).toList();
    final cursor = page.isEmpty ? (since > revision ? since : revision) : page.last['revision'] as int;
    return _json({'records': page, 'revision': cursor, 'more': newer.length > pullLimit});
  }

  Future<http.Response> _push(Map<String, dynamic> body) async {
    pushes++;
    await duringPush?.call();
    final accepted = <Map<String, Object>>[], conflicts = <Map<String, Object?>>[];
    for (final change in (body['changes'] as List).cast<Map<String, dynamic>>()) {
      final id = change['id'] as String;
      final current = records[id];
      final expected = (current == null ? 0 : current['version'] as int) + 1;
      if (change['version'] != expected) {
        conflicts.add({'id': id, 'reason': 'version_conflict', 'current': current});
        continue;
      }
      revision++;
      records[id] = {
        'id': id,
        'version': change['version'],
        'deleted': change['deleted'],
        'nonce': change['nonce'],
        'ct': change['ct'],
        'revision': revision,
      };
      accepted.add({'id': id, 'version': change['version'] as int, 'revision': revision});
    }
    return _json({'accepted': accepted, 'conflicts': conflicts, 'revision': revision});
  }
}
