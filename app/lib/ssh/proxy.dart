import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

enum ProxyKind { socks5, http }

/// A proxy to open the connection through: SOCKS5, or HTTP with CONNECT.
class ProxyConfig {
  const ProxyConfig({required this.kind, required this.host, required this.port, this.username, this.password});

  final ProxyKind kind;
  final String host;
  final int port;
  final String? username;
  final String? password;

  String get label => '$host:$port';
}

enum ProxyProblem {
  /// The proxy itself could not be reached.
  unreachable,

  /// The proxy refused the username or password, or wants one.
  authFailed,

  /// The proxy could not reach the target, or would not.
  targetFailed,

  /// The proxy answered something this client does not understand.
  protocol,
}

class ProxyException implements Exception {
  const ProxyException(this.problem, [this.detail]);
  final ProxyProblem problem;
  final String? detail;

  @override
  String toString() => 'ProxyException($problem${detail == null ? '' : ': $detail'})';
}

/// Opens a connection to [host]:[port] through [proxy], ready for SSH.
Future<SSHSocket> connectThroughProxy(
  ProxyConfig proxy,
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final Socket socket;
  try {
    socket = await Socket.connect(proxy.host, proxy.port, timeout: timeout);
  } on SocketException catch (e) {
    throw ProxyException(ProxyProblem.unreachable, e.message);
  }
  final reader = _Reader(socket);
  try {
    await switch (proxy.kind) {
      ProxyKind.socks5 => _socks5(proxy, reader, socket, host, port),
      ProxyKind.http => _httpConnect(proxy, reader, socket, host, port),
    }.timeout(timeout);
  } on TimeoutException {
    socket.destroy();
    throw const ProxyException(ProxyProblem.unreachable, 'timed out');
  } catch (_) {
    socket.destroy();
    rethrow;
  }
  return _ProxiedSocket(socket, reader.handOff());
}

Future<void> _socks5(ProxyConfig proxy, _Reader reader, Socket socket, String host, int port) async {
  final user = proxy.username ?? '';
  final withPassword = user.isNotEmpty;
  // Greeting: the authentication methods offered (0 none, 2 password).
  socket.add(withPassword ? [5, 2, 0, 2] : [5, 1, 0]);
  final choice = await reader.read(2);
  if (choice[0] != 5) throw const ProxyException(ProxyProblem.protocol, 'not a SOCKS5 proxy');
  switch (choice[1]) {
    case 0:
      break;
    case 2:
      if (!withPassword) throw const ProxyException(ProxyProblem.authFailed);
      final u = utf8.encode(user);
      final p = utf8.encode(proxy.password ?? '');
      if (u.length > 255 || p.length > 255) throw const ProxyException(ProxyProblem.authFailed);
      socket.add([1, u.length, ...u, p.length, ...p]);
      final status = await reader.read(2);
      if (status[1] != 0) throw const ProxyException(ProxyProblem.authFailed);
    default:
      throw const ProxyException(ProxyProblem.authFailed);
  }

  // CONNECT by name: the proxy resolves it, so names that only it knows work.
  final name = utf8.encode(host);
  if (name.length > 255) throw const ProxyException(ProxyProblem.targetFailed, 'name too long');
  socket.add([5, 1, 0, 3, name.length, ...name, port >> 8, port & 0xff]);
  final reply = await reader.read(4);
  if (reply[0] != 5) throw const ProxyException(ProxyProblem.protocol);
  if (reply[1] != 0) throw ProxyException(ProxyProblem.targetFailed, 'SOCKS5 reply ${reply[1]}');
  // The bound address that follows is not needed, but must be read past.
  final addressLength = switch (reply[3]) {
    1 => 4,
    4 => 16,
    3 => (await reader.read(1))[0],
    _ => throw const ProxyException(ProxyProblem.protocol),
  };
  await reader.read(addressLength + 2);
}

Future<void> _httpConnect(ProxyConfig proxy, _Reader reader, Socket socket, String host, int port) async {
  final authority = host.contains(':') ? '[$host]:$port' : '$host:$port';
  final request = StringBuffer()
    ..write('CONNECT $authority HTTP/1.1\r\n')
    ..write('Host: $authority\r\n');
  final user = proxy.username ?? '';
  if (user.isNotEmpty) {
    request.write('Proxy-Authorization: Basic ${base64.encode(utf8.encode('$user:${proxy.password ?? ''}'))}\r\n');
  }
  request.write('\r\n');
  socket.add(utf8.encode(request.toString()));

  final header = await reader.readHeader();
  final status = RegExp(r'^HTTP/1\.[01] (\d{3})').firstMatch(header);
  if (status == null) throw const ProxyException(ProxyProblem.protocol, 'not an HTTP proxy');
  final code = int.parse(status.group(1)!);
  if (code == 407) throw const ProxyException(ProxyProblem.authFailed);
  if (code < 200 || code > 299) throw ProxyException(ProxyProblem.targetFailed, 'HTTP $code');
}

/// Reads the proxy's handshake from the socket, then hands the rest of the
/// stream, including bytes that came early, to the SSH connection.
class _Reader {
  _Reader(Socket socket) {
    _subscription = socket.listen(
      (data) {
        final out = _out;
        if (out != null) {
          out.add(data);
        } else {
          _buffer.add(data);
          _wake();
        }
      },
      onError: (Object e) {
        _error = e;
        _out?.addError(e);
        _wake();
      },
      onDone: () {
        _closed = true;
        _out?.close();
        _wake();
      },
    );
  }

  late final StreamSubscription<Uint8List> _subscription;
  final _buffer = BytesBuilder();
  StreamController<Uint8List>? _out;
  Completer<void>? _waiting;
  Object? _error;
  var _closed = false;

  void _wake() {
    _waiting?.complete();
    _waiting = null;
  }

  Future<void> _more() async {
    if (_error != null || _closed) {
      throw ProxyException(ProxyProblem.targetFailed, _error?.toString() ?? 'the proxy closed the connection');
    }
    await (_waiting = Completer<void>()).future;
  }

  Future<Uint8List> read(int n) async {
    while (_buffer.length < n) {
      await _more();
    }
    final all = _buffer.takeBytes();
    _buffer.add(Uint8List.sublistView(all, n));
    return Uint8List.sublistView(all, 0, n);
  }

  /// An HTTP response header, up to its blank line.
  Future<String> readHeader() async {
    while (true) {
      final bytes = _buffer.toBytes();
      for (var i = 3; i < bytes.length; i++) {
        if (bytes[i - 3] == 13 && bytes[i - 2] == 10 && bytes[i - 1] == 13 && bytes[i] == 10) {
          _buffer.clear();
          _buffer.add(Uint8List.sublistView(bytes, i + 1));
          return latin1.decode(Uint8List.sublistView(bytes, 0, i + 1));
        }
      }
      if (bytes.length > 16 * 1024) throw const ProxyException(ProxyProblem.protocol, 'header too long');
      await _more();
    }
  }

  Stream<Uint8List> handOff() {
    final out = StreamController<Uint8List>(
      onPause: _subscription.pause,
      onResume: _subscription.resume,
      onCancel: _subscription.cancel,
    );
    _out = out;
    final early = _buffer.takeBytes();
    if (early.isNotEmpty) out.add(early);
    if (_closed) out.close();
    return out.stream;
  }
}

class _ProxiedSocket implements SSHSocket {
  _ProxiedSocket(this._socket, this.stream);

  final Socket _socket;

  @override
  final Stream<Uint8List> stream;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> close() => _socket.close();

  @override
  void destroy() => _socket.destroy();

  @override
  Future<void> flush() => _socket.flush();
}
