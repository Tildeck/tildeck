import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import 'known_hosts.dart';
import 'proxy.dart';

/// Where to connect and how to authenticate.
class ConnectionTarget {
  const ConnectionTarget({
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKey,
    this.passphrase,
    this.startupCommand,
    this.environment = const {},
    this.hostId,
    this.jump,
    this.agentKeys,
    this.proxy,
  });

  final String host;
  final int port;
  final String username;
  final String? password;

  /// A private key in PEM or OpenSSH format.
  final String? privateKey;
  final String? passphrase;

  /// Sent to the shell once it opens: a startup snippet.
  final String? startupCommand;

  /// Environment variables requested for the shell.
  final Map<String, String> environment;

  /// The saved host this target came from, for the history.
  final String? hostId;

  /// The server to connect through; the connection to this target is
  /// tunneled inside it, so the address is as that server sees it.
  final ConnectionTarget? jump;

  /// Keys offered to the server through agent forwarding; null turns it
  /// off. Keys that cannot be read (a passphrase not saved) are left out.
  final List<({String privateKey, String? passphrase})>? agentKeys;

  /// The proxy to connect through, used only when this target is connected
  /// to directly; through a jump host, the jump host's own setting counts.
  final ProxyConfig? proxy;

  String get label => port == 22 ? '$username@$host' : '$username@$host:$port';

  /// The same target with another command to run once the shell opens.
  ConnectionTarget withStartupCommand(String? command) => ConnectionTarget(
    host: host,
    port: port,
    username: username,
    password: password,
    privateKey: privateKey,
    passphrase: passphrase,
    startupCommand: command,
    environment: environment,
    hostId: hostId,
    jump: jump,
    agentKeys: agentKeys,
    proxy: proxy,
  );
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
  const ConnectException(this.problem, [this.detail, this.via]);
  final ConnectProblem problem;
  final String? detail;

  /// The jump host the failure happened at, when not the target itself.
  final String? via;

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

  final KnownHosts knownHosts;
  final Duration timeout;

  Future<SSHClient> connect(ConnectionTarget target, {required HostKeyPrompt promptHostKey}) async {
    final jump = target.jump;
    if (jump == null) return _connect(target, promptHostKey, null);
    final SSHClient via;
    try {
      via = await connect(jump, promptHostKey: promptHostKey);
    } on ConnectException catch (e) {
      throw ConnectException(e.problem, e.detail, e.via ?? jump.label);
    }
    try {
      final client = await _connect(target, promptHostKey, via);
      // The tunnel lives as long as the connection inside it.
      unawaited(client.done.catchError((_) {}).whenComplete(via.close));
      return client;
    } catch (_) {
      via.close();
      rethrow;
    }
  }

  Future<SSHClient> _connect(ConnectionTarget target, HostKeyPrompt promptHostKey, SSHClient? via) async {
    final identities = _identities(target);

    final SSHSocket socket;
    final proxy = target.proxy;
    try {
      socket = via != null
          ? await via.forwardLocal(target.host, target.port).timeout(timeout)
          : proxy != null
          ? await connectThroughProxy(proxy, target.host, target.port, timeout: timeout)
          : await SSHSocket.connect(target.host, target.port, timeout: timeout);
    } on ProxyException catch (e) {
      throw switch (e.problem) {
        ProxyProblem.unreachable => ConnectException(ConnectProblem.unreachable, e.detail, proxy!.label),
        ProxyProblem.authFailed => ConnectException(ConnectProblem.authFailed, e.detail, proxy!.label),
        ProxyProblem.protocol => ConnectException(ConnectProblem.disconnected, e.detail, proxy!.label),
        // The proxy is fine; the target is what it could not reach.
        ProxyProblem.targetFailed => ConnectException(ConnectProblem.unreachable, e.detail),
      };
    } on TimeoutException {
      throw const ConnectException(ConnectProblem.timeout);
    } on SocketException catch (e) {
      throw ConnectException(ConnectProblem.unreachable, e.message);
    } on SSHChannelOpenError catch (e) {
      // The jump host could not reach the target.
      throw ConnectException(ConnectProblem.unreachable, e.description);
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
      // Like ssh(1): a refused environment variable, agent forwarding, or pty
      // is skipped, and only a refused shell or command fails the session.
      pipelineChannelRequests: true,
      agentHandler: target.agentKeys == null ? null : SSHKeyPairAgent(_agentIdentities(target.agentKeys!)),
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

  static List<SSHKeyPair> _agentIdentities(List<({String privateKey, String? passphrase})> keys) => [
    for (final k in keys) ...?_readable(k.privateKey, k.passphrase),
  ];

  static List<SSHKeyPair>? _readable(String key, String? passphrase) {
    try {
      return SSHKeyPair.fromPem(key.trim(), (passphrase?.isEmpty ?? true) ? null : passphrase);
    } catch (_) {
      return null;
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
