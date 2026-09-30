import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import 'known_hosts.dart';

/// Where to connect and how to authenticate.
class ConnectionTarget {
  const ConnectionTarget({
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKey,
    this.passphrase,
  });

  final String host;
  final int port;
  final String username;
  final String? password;

  /// A private key in PEM or OpenSSH format.
  final String? privateKey;
  final String? passphrase;

  String get label => port == 22 ? '$username@$host' : '$username@$host:$port';
}

/// Why a connection failed. Each one maps to a localized message.
enum ConnectProblem {
  unreachable,
  timeout,
  authFailed,
  hostKeyRejected,
  keyInvalid,
  keyPassphraseRequired,
  keyPassphraseWrong,
  disconnected,
}

class ConnectException implements Exception {
  const ConnectException(this.problem, [this.detail]);
  final ConnectProblem problem;
  final String? detail;

  @override
  String toString() => 'ConnectException($problem${detail == null ? '' : ': $detail'})';
}

/// Asks the user whether to trust a host key. Called only for an unknown or
/// a changed key; a trusted key connects without asking.
typedef HostKeyPrompt =
    Future<bool> Function({
      required ConnectionTarget target,
      required KnownHost presented,
      required HostKeyStatus status,
      KnownHost? previous,
    });

/// Opens SSH connections with host key verification against [knownHosts].
class SshConnector {
  SshConnector({required this.knownHosts, this.timeout = const Duration(seconds: 15)});

  final KnownHostsStore knownHosts;
  final Duration timeout;

  Future<SSHClient> connect(ConnectionTarget target, {required HostKeyPrompt promptHostKey}) async {
    final identities = _identities(target);

    final SSHSocket socket;
    try {
      socket = await SSHSocket.connect(target.host, target.port, timeout: timeout);
    } on TimeoutException {
      throw const ConnectException(ConnectProblem.timeout);
    } on SocketException catch (e) {
      throw ConnectException(ConnectProblem.unreachable, e.message);
    }

    var hostKeyRejected = false;
    final client = SSHClient(
      socket,
      username: target.username,
      identities: identities,
      onPasswordRequest: target.password == null ? null : () => target.password,
      // Keyboard-interactive servers ask for the password this way.
      onUserInfoRequest: target.password == null
          ? null
          : (request) => [for (final _ in request.prompts) target.password!],
      handshakeTimeout: timeout,
      authTimeout: timeout,
      onVerifyHostKey: (type, fingerprintBytes) async {
        final presented = KnownHost(type: type, fingerprint: utf8.decode(fingerprintBytes));
        final status = await knownHosts.check(target.host, target.port, presented);
        if (status == HostKeyStatus.trusted) return true;
        final previous = await knownHosts.lookup(target.host, target.port);
        final accepted = await promptHostKey(target: target, presented: presented, status: status, previous: previous);
        if (!accepted) {
          hostKeyRejected = true;
          return false;
        }
        await knownHosts.trust(target.host, target.port, presented);
        return true;
      },
    );

    try {
      await client.authenticated;
      return client;
    } catch (e) {
      client.close();
      // A refused host key closes the transport, which surfaces as an
      // authentication abort; the refusal is the real reason.
      if (hostKeyRejected || e is SSHHostkeyError) throw const ConnectException(ConnectProblem.hostKeyRejected);
      if (e is SSHAuthError) throw const ConnectException(ConnectProblem.authFailed);
      if (e is TimeoutException) throw const ConnectException(ConnectProblem.timeout);
      throw ConnectException(ConnectProblem.disconnected, '$e');
    }
  }

  static List<SSHKeyPair>? _identities(ConnectionTarget target) {
    final key = target.privateKey?.trim();
    if (key == null || key.isEmpty) return null;
    final passphrase = (target.passphrase?.isEmpty ?? true) ? null : target.passphrase;
    try {
      if (SSHKeyPair.isEncryptedPem(key) && passphrase == null) {
        throw const ConnectException(ConnectProblem.keyPassphraseRequired);
      }
      return SSHKeyPair.fromPem(key, passphrase);
    } on ConnectException {
      rethrow;
    } on SSHKeyDecryptError {
      throw const ConnectException(ConnectProblem.keyPassphraseWrong);
    } catch (_) {
      throw const ConnectException(ConnectProblem.keyInvalid);
    }
  }
}
