// Small SOCKS5 and HTTP CONNECT proxies for tests, each optionally asking
// for a username and password, relaying to wherever the client asks.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class FakeProxy {
  FakeProxy._(this._server, this.username, this.password);

  final ServerSocket _server;
  final String? username;
  final String? password;

  /// Every target asked for, as host:port.
  final targets = <String>[];

  int get port => _server.port;

  static Future<FakeProxy> socks5({String? username, String? password}) async {
    final proxy = FakeProxy._(await ServerSocket.bind('127.0.0.1', 0), username, password);
    proxy._server.listen(proxy._socks5);
    return proxy;
  }

  static Future<FakeProxy> http({String? username, String? password}) async {
    final proxy = FakeProxy._(await ServerSocket.bind('127.0.0.1', 0), username, password);
    proxy._server.listen(proxy._http);
    return proxy;
  }

  Future<void> close() => _server.close();

  Future<void> _socks5(Socket client) async {
    final input = _Input(client);
    try {
      final greeting = await input.read(2);
      final methods = await input.read(greeting[1]);
      if (username != null) {
        if (!methods.contains(2)) return client.add([5, 0xff]);
        client.add([5, 2]);
        await input.read(1);
        final user = utf8.decode(await input.read((await input.read(1))[0]));
        final pass = utf8.decode(await input.read((await input.read(1))[0]));
        final ok = user == username && pass == password;
        client.add([1, ok ? 0 : 1]);
        if (!ok) return client.destroy();
      } else {
        client.add([5, 0]);
      }
      final request = await input.read(4);
      final String host;
      switch (request[3]) {
        case 1:
          host = (await input.read(4)).join('.');
        case 3:
          host = utf8.decode(await input.read((await input.read(1))[0]));
        default:
          return client.destroy();
      }
      final portBytes = await input.read(2);
      final port = portBytes[0] << 8 | portBytes[1];
      targets.add('$host:$port');
      final Socket target;
      try {
        target = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      } catch (_) {
        client.add([5, 5, 0, 1, 0, 0, 0, 0, 0, 0]);
        return client.destroy();
      }
      client.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 0]);
      input.relay(target);
    } catch (_) {
      client.destroy();
    }
  }

  Future<void> _http(Socket client) async {
    final input = _Input(client);
    try {
      final header = await input.readHeader();
      final line = RegExp(r'^CONNECT (\S+):(\d+) HTTP/1\.[01]').firstMatch(header);
      if (line == null) {
        client.write('HTTP/1.1 400 Bad Request\r\n\r\n');
        return client.destroy();
      }
      if (username != null) {
        final expected = 'Basic ${base64.encode(utf8.encode('$username:$password'))}';
        if (!header.contains('Proxy-Authorization: $expected\r\n')) {
          client.write('HTTP/1.1 407 Proxy Authentication Required\r\n\r\n');
          return client.destroy();
        }
      }
      final host = line.group(1)!;
      final port = int.parse(line.group(2)!);
      targets.add('$host:$port');
      final Socket target;
      try {
        target = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      } catch (_) {
        client.write('HTTP/1.1 502 Bad Gateway\r\n\r\n');
        return client.destroy();
      }
      client.write('HTTP/1.1 200 Connection established\r\n\r\n');
      input.relay(target);
    } catch (_) {
      client.destroy();
    }
  }
}

/// Buffered reading of a socket, then relaying it once the handshake is done.
class _Input {
  _Input(this.socket) {
    _subscription = socket.listen(
      (data) {
        final target = _target;
        if (target != null) {
          target.add(data);
        } else {
          _buffer.add(data);
          _waiting?.complete();
          _waiting = null;
        }
      },
      onDone: () {
        _done = true;
        _target?.destroy();
        _waiting?.complete();
        _waiting = null;
      },
      onError: (_) {},
    );
  }

  final Socket socket;
  late final StreamSubscription<Uint8List> _subscription;
  final _buffer = BytesBuilder();
  Completer<void>? _waiting;
  Socket? _target;
  var _done = false;

  Future<Uint8List> read(int n) async {
    while (_buffer.length < n) {
      if (_done) throw StateError('closed');
      await (_waiting = Completer<void>()).future;
    }
    final all = _buffer.takeBytes();
    _buffer.add(Uint8List.sublistView(all, n));
    return Uint8List.sublistView(all, 0, n);
  }

  Future<String> readHeader() async {
    while (true) {
      final text = latin1.decode(_buffer.toBytes());
      final end = text.indexOf('\r\n\r\n');
      if (end >= 0) {
        final bytes = _buffer.takeBytes();
        _buffer.add(Uint8List.sublistView(bytes, end + 4));
        return text.substring(0, end + 4);
      }
      if (_done) throw StateError('closed');
      await (_waiting = Completer<void>()).future;
    }
  }

  void relay(Socket target) {
    _target = target;
    final early = _buffer.takeBytes();
    if (early.isNotEmpty) target.add(early);
    target.listen(socket.add, onDone: socket.destroy, onError: (_) => socket.destroy());
    if (_done) target.destroy();
    _subscription.resume();
  }
}
