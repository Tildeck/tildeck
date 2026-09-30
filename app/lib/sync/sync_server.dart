import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:tildeck_api/api.dart' as api;

import '../server_check.dart';
import '../vault/vault.dart';
import '../vault/vault_crypto.dart';

/// A request the server refused or never answered. [code] is the server's
/// stable error code (server/app/protocol.py); null when there was no
/// answer or the answer was not a Tildeck error.
class SyncFailure implements Exception {
  const SyncFailure(this.status, this.code);

  /// 0 when the server was not reached.
  final int status;
  final String? code;

  bool get unreachable => status == 0 || status >= 500;

  @override
  String toString() => 'SyncFailure($status, $code)';
}

/// The account and vault keys a signed-in device receives.
class SignedIn {
  const SignedIn({
    required this.token,
    required this.emailVerified,
    required this.vaultId,
    required this.kdf,
    required this.wrapPw,
  });

  final String token;
  final bool emailVerified;
  final String vaultId;
  final KdfParams kdf;
  final Sealed wrapPw;
}

sealed class SigninOutcome {
  const SigninOutcome();
}

class SigninActive extends SigninOutcome {
  const SigninActive(this.signedIn);
  final SignedIn signedIn;
}

/// A new device waits for approval; only it holds [claimToken].
class SigninPending extends SigninOutcome {
  const SigninPending({required this.deviceId, required this.claimToken, required this.emailApproval});
  final String deviceId;
  final String claimToken;

  /// An approval link was also sent by email.
  final bool emailApproval;
}

class PullPage {
  const PullPage(this.records, this.revision, this.more);
  final List<StoredRecord> records;
  final int revision;
  final bool more;
}

class PushResult {
  const PushResult(this.accepted, this.conflicts);

  /// The changes the server stored, as they were sent.
  final List<StoredRecord> accepted;

  /// Refused changes, with the server's current record (null when the
  /// server has no such record).
  final List<(String, StoredRecord?)> conflicts;
}

/// The sync server's account and sync API (docs/security-model.md), over the
/// client generated from server/openapi.json. Every request carries the
/// protocol version; signed-in requests carry the device token.
class SyncServer {
  SyncServer(String baseAddress, {http.Client? client})
    : _client = api.ApiClient(basePath: baseAddress)..client = client ?? http.Client();

  final api.ApiClient _client;

  api.AccountApi get _account => api.AccountApi(_client);
  api.SyncApi get _sync => api.SyncApi(_client);

  static String _bearer(String token) => 'Bearer $token';

  static String b64(List<int> bytes) => base64.encode(bytes);

  Future<T> _call<T>(Future<T?> Function() request) async {
    final T? result;
    try {
      result = await request();
    } on api.ApiException catch (e) {
      if (e.innerException != null) throw const SyncFailure(0, null);
      String? code;
      try {
        final body = jsonDecode(e.message ?? '');
        if (body is Map && body['error'] is String) code = body['error'] as String;
      } on FormatException {
        code = null;
      }
      throw SyncFailure(e.code, code);
    }
    // Every call here that returns a value has a body on success.
    if (result == null && null is! T) throw const SyncFailure(0, null);
    return result as T;
  }

  static api.KdfParams _kdfOut(KdfParams k) =>
      api.KdfParams(alg: 'argon2id13', ops: k.opsLimit, mem: k.memLimit, salt: b64(k.salt));

  static KdfParams _kdfIn(api.KdfParams k) =>
      KdfParams.fromJson({'alg': k.alg, 'ops': k.ops, 'mem': k.mem, 'salt': k.salt});

  static api.ModelSealed _sealedOut(Sealed s) => api.ModelSealed(nonce: b64(s.nonce), ct: b64(s.ciphertext));

  static Sealed _sealedIn(api.ModelSealed s) => Sealed.fromJson({'nonce': s.nonce, 'ct': s.ct});

  static SignedIn _signedIn(api.SignedIn s) => SignedIn(
    token: s.deviceToken,
    emailVerified: s.emailVerified,
    vaultId: s.vault.vaultId,
    kdf: _kdfIn(s.vault.kdf),
    wrapPw: _sealedIn(s.vault.wrapPw),
  );

  /// The Argon2id parameters and salt for [email]. The server answers for
  /// any address, so this reveals nothing about which accounts exist.
  Future<KdfParams> prelogin(String email) async {
    final res = await _call(
      () => _account.prelogin(api.PreloginRequest(email: email), tildeckProtocol: kProtocolVersion),
    );
    return _kdfIn(res.kdf);
  }

  Future<SignedIn> register({
    required String email,
    required String locale,
    required String vaultId,
    required KdfParams kdf,
    required List<int> authKey,
    required List<int> recoveryAuthKey,
    required Sealed wrapPw,
    required Sealed wrapRk,
    required String deviceId,
    required String deviceName,
  }) async {
    final res = await _call(
      () => _account.register(
        api.RegisterRequest(
          email: email,
          locale: locale,
          vaultId: vaultId,
          kdf: _kdfOut(kdf),
          authKey: b64(authKey),
          recoveryAuthKey: b64(recoveryAuthKey),
          wrapPw: _sealedOut(wrapPw),
          wrapRk: _sealedOut(wrapRk),
          device: api.DeviceInfo(id: deviceId, name: deviceName),
        ),
        tildeckProtocol: kProtocolVersion,
      ),
    );
    return _signedIn(res);
  }

  Future<SigninOutcome> signin({
    required String email,
    required List<int> authKey,
    required String deviceId,
    required String deviceName,
  }) async {
    final res = await _call(
      () => _account.signin(
        api.SigninRequest(
          email: email,
          authKey: b64(authKey),
          device: api.DeviceInfo(id: deviceId, name: deviceName),
        ),
        tildeckProtocol: kProtocolVersion,
      ),
    );
    final signedIn = res.signedIn;
    if (res.status == api.SigninResultStatusEnum.active && signedIn != null) return SigninActive(_signedIn(signedIn));
    final deviceIdOut = res.deviceId, claimToken = res.claimToken;
    if (deviceIdOut == null || claimToken == null) throw const SyncFailure(0, null);
    return SigninPending(deviceId: deviceIdOut, claimToken: claimToken, emailApproval: res.emailApproval ?? false);
  }

  /// The device token of an approved device. Before approval the server
  /// answers 409 `device_pending`.
  Future<SignedIn> claim(String deviceId, String claimToken) async {
    final res = await _call(
      () => _account.claimDevice(
        api.ClaimRequest(deviceId: deviceId, claimToken: claimToken),
        tildeckProtocol: kProtocolVersion,
      ),
    );
    return _signedIn(res);
  }

  Future<api.AccountView> account(String token) =>
      _call(() => _account.getAccount(tildeckProtocol: kProtocolVersion, authorization: _bearer(token)));

  Future<void> approve(String token, String deviceId) =>
      _call(() => _account.approveDevice(deviceId, tildeckProtocol: kProtocolVersion, authorization: _bearer(token)));

  Future<void> revoke(String token, String deviceId) =>
      _call(() => _account.revokeDevice(deviceId, tildeckProtocol: kProtocolVersion, authorization: _bearer(token)));

  Future<void> resendVerification(String token) =>
      _call(() => _account.resendVerification(tildeckProtocol: kProtocolVersion, authorization: _bearer(token)));

  static StoredRecord _recordIn(api.StoredRecord r) => StoredRecord(
    id: r.id,
    version: r.version,
    deleted: r.deleted,
    sealed: r.deleted || r.ct == null || r.nonce == null ? null : Sealed.fromJson({'nonce': r.nonce, 'ct': r.ct}),
  );

  Future<PullPage> pull(String token, int since) async {
    final res = await _call(
      () => _sync.pullRecords(since: since, tildeckProtocol: kProtocolVersion, authorization: _bearer(token)),
    );
    return PullPage([for (final r in res.records) _recordIn(r)], res.revision, res.more);
  }

  /// Sends up to 500 changes (the server's limit per push).
  Future<PushResult> push(String token, List<StoredRecord> changes) async {
    final res = await _call(
      () => _sync.pushRecords(
        api.PushRequest(
          changes: [
            for (final c in changes)
              api.SyncRecord(
                id: c.id,
                version: c.version,
                deleted: c.deleted,
                nonce: c.sealed == null ? null : b64(c.sealed!.nonce),
                ct: c.sealed == null ? null : b64(c.sealed!.ciphertext),
              ),
          ],
        ),
        tildeckProtocol: kProtocolVersion,
        authorization: _bearer(token),
      ),
    );
    final sent = {for (final c in changes) c.id: c};
    return PushResult(
      [
        for (final a in res.accepted)
          if (sent[a.id] case final c? when c.version == a.version) c,
      ],
      [for (final c in res.conflicts) (c.id, c.current == null ? null : _recordIn(c.current!))],
    );
  }
}
