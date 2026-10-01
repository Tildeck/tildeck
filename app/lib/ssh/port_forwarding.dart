import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../vault/models.dart';

/// A rule that is running: its connection, and what it listens on.
class ActiveForward {
  ActiveForward(this.rule, this._client);

  final PortForwardEntry rule;
  final SSHClient _client;

  ServerSocket? _server;
  SSHRemoteForward? _remote;
  SSHDynamicForward? _dynamic;
  final _open = <Socket>{};

  /// The port actually listened on (a rule may ask for any free port).
  int? boundPort;

  /// Connections carried so far.
  int connections = 0;

  Future<void> stop() async {
    await _server?.close();
    final remote = _remote;
    if (remote != null) {
      // SSHRemoteForward.close() cancels without waiting, and closing the
      // client next would fail that request unhandled: cancel first.
      try {
        await _client.cancelForwardRemote(remote).timeout(const Duration(seconds: 2));
      } catch (_) {}
      remote.close();
    }
    await _dynamic?.close();
    for (final s in _open.toList()) {
      s.destroy();
    }
    _client.close();
  }
}

/// Why a rule could not start. Each maps to a localized message.
enum ForwardProblem { connectFailed, portInUse, refusedByServer, failed }

class ForwardException implements Exception {
  const ForwardException(this.problem);
  final ForwardProblem problem;
}

/// Starts [rule] over an authenticated [client]: local forwarding listens
/// here and connects out from the server, remote forwarding listens on the
/// server and connects out from here, and dynamic forwarding is a SOCKS5
/// proxy here that connects out from the server.
Future<ActiveForward> startForward(PortForwardEntry rule, SSHClient client) async {
  final active = ActiveForward(rule, client);
  try {
    switch (rule.kind) {
      case ForwardKind.local:
        final server = await ServerSocket.bind(rule.bindHost, rule.bindPort);
        active._server = server;
        active.boundPort = server.port;
        server.listen((socket) async {
          active.connections++;
          active._open.add(socket);
          try {
            final channel = await client.forwardLocal(rule.destHost, rule.destPort);
            _pipe(socket, channel, () => active._open.remove(socket));
          } catch (_) {
            socket.destroy();
            active._open.remove(socket);
          }
        });
      case ForwardKind.remote:
        final remote = await client.forwardRemote(host: rule.bindHost, port: rule.bindPort);
        if (remote == null) throw const ForwardException(ForwardProblem.refusedByServer);
        active._remote = remote;
        active.boundPort = remote.port;
        remote.connections.listen((channel) async {
          active.connections++;
          try {
            final socket = await Socket.connect(rule.destHost, rule.destPort, timeout: const Duration(seconds: 10));
            active._open.add(socket);
            _pipe(socket, channel, () => active._open.remove(socket));
          } catch (_) {
            channel.destroy();
          }
        });
      case ForwardKind.dynamic:
        final socks = await client.forwardDynamic(bindHost: rule.bindHost, bindPort: rule.bindPort);
        active._dynamic = socks;
        active.boundPort = socks.port;
    }
  } on SocketException {
    client.close();
    throw const ForwardException(ForwardProblem.portInUse);
  } on ForwardException {
    client.close();
    rethrow;
  } catch (_) {
    client.close();
    throw const ForwardException(ForwardProblem.failed);
  }
  return active;
}

/// Copies bytes both ways until either side closes, then closes the other.
void _pipe(Socket socket, SSHForwardChannel channel, VoidCallback onClosed) {
  var closed = false;
  void close() {
    if (closed) return;
    closed = true;
    socket.destroy();
    channel.destroy();
    onClosed();
  }

  socket.listen(
    (data) => channel.sink.add(data),
    onDone: () => channel.sink.close(),
    onError: (_) => close(),
    cancelOnError: true,
  );
  channel.stream.listen(
    (Uint8List data) => socket.add(data),
    onDone: close,
    onError: (_) => close(),
    cancelOnError: true,
  );
  channel.done.then((_) => close(), onError: (_) => close());
}

/// The rules that run, by rule id, for the whole app: they keep running
/// while the vault is locked, like open sessions.
class ForwardManager extends ChangeNotifier {
  final _active = <String, ActiveForward>{};
  final _starting = <String>{};
  final _problems = <String, ForwardProblem>{};

  ActiveForward? active(String id) => _active[id];
  bool isStarting(String id) => _starting.contains(id);
  ForwardProblem? problemOf(String id) => _problems[id];

  /// Starts [rule], connecting with [connect]. A failure is kept for the
  /// rule and shown; the rule stays off.
  Future<void> start(PortForwardEntry rule, Future<SSHClient> Function() connect) async {
    if (_active.containsKey(rule.id) || !_starting.add(rule.id)) return;
    _problems.remove(rule.id);
    notifyListeners();
    try {
      final SSHClient client;
      try {
        client = await connect();
      } catch (_) {
        throw const ForwardException(ForwardProblem.connectFailed);
      }
      final active = await startForward(rule, client);
      _active[rule.id] = active;
      // The connection dropping turns the rule off.
      unawaited(client.done.then((_) => _ended(rule.id, active), onError: (_) => _ended(rule.id, active)));
    } on ForwardException catch (e) {
      _problems[rule.id] = e.problem;
    } finally {
      _starting.remove(rule.id);
      notifyListeners();
    }
  }

  void _ended(String id, ActiveForward active) {
    if (_active[id] != active) return;
    _active.remove(id);
    active.stop();
    notifyListeners();
  }

  Future<void> stop(String id) async {
    final active = _active.remove(id);
    notifyListeners();
    await active?.stop();
  }

  Future<void> stopAll() async {
    for (final id in _active.keys.toList()) {
      await stop(id);
    }
  }

  @override
  void dispose() {
    stopAll();
    super.dispose();
  }
}
