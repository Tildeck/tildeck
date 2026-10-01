import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Telnet command and option codes (RFC 854, 855, 857, 858, 1073, 1091).
abstract final class _T {
  static const se = 240;
  static const sb = 250;
  static const will = 251;
  static const wont = 252;
  static const do_ = 253;
  static const dont = 254;
  static const iac = 255;

  static const echo = 1;
  static const suppressGoAhead = 3;
  static const terminalType = 24;
  static const windowSize = 31;

  static const ttypeIs = 0;
  static const ttypeSend = 1;
}

/// A Telnet session over [socket]: separates the server's option
/// negotiation from what it prints, answers it, and escapes what is typed.
///
/// The client offers its terminal type and window size, lets the server
/// echo and suppress go-ahead, and refuses every other option.
class TelnetChannel {
  TelnetChannel(this._socket, {this.terminalType = 'XTERM-256COLOR', this.width = 80, this.height = 24}) {
    _subscription = _socket.stream.listen(
      _receive,
      onError: (Object e) => _close(),
      onDone: _close,
      cancelOnError: true,
    );
  }

  final SSHSocket _socket;
  final String terminalType;
  late final StreamSubscription<Uint8List> _subscription;
  final _output = StreamController<Uint8List>();
  final _done = Completer<void>();

  /// The window size told to the server, in characters.
  int width;
  int height;

  /// Options this side has agreed to perform (WILL sent), and the server's
  /// options this side has agreed to (DO sent): answers only on a change,
  /// so two sides never loop (RFC 854).
  final _ours = <int>{};
  final _theirs = <int>{};

  /// What the server prints, without the negotiation.
  Stream<Uint8List> get output => _output.stream;

  /// Completes when the connection ends.
  Future<void> get done => _done.future;

  /// Sends what is typed: 255 doubled, and a bare CR as CR NUL.
  void write(List<int> data) {
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < data.length; i++) {
      final b = data[i];
      if (b == _T.iac) {
        out
          ..addByte(_T.iac)
          ..addByte(_T.iac);
      } else if (b == 13 && (i + 1 >= data.length || data[i + 1] != 10)) {
        out
          ..addByte(13)
          ..addByte(0);
      } else {
        out.addByte(b);
      }
    }
    _send(out.takeBytes());
  }

  void resize(int width, int height) {
    this.width = width;
    this.height = height;
    if (_ours.contains(_T.windowSize)) _sendWindowSize();
  }

  void close() {
    _socket.destroy();
    _close();
  }

  void _close() {
    if (_done.isCompleted) return;
    _subscription.cancel();
    _output.close();
    _done.complete();
  }

  void _send(List<int> bytes) {
    if (_done.isCompleted) return;
    try {
      _socket.sink.add(bytes);
    } catch (_) {
      _close();
    }
  }

  // Parser state, kept across reads: a command may arrive split.
  var _state = _ParseState.data;
  var _verb = 0;
  final _sub = BytesBuilder();

  void _receive(Uint8List chunk) {
    final text = BytesBuilder(copy: false);
    for (final b in chunk) {
      switch (_state) {
        case _ParseState.data:
          if (b == _T.iac) {
            _state = _ParseState.iac;
          } else {
            text.addByte(b);
          }
        case _ParseState.iac:
          switch (b) {
            case _T.iac:
              text.addByte(_T.iac);
              _state = _ParseState.data;
            case _T.will || _T.wont || _T.do_ || _T.dont:
              _verb = b;
              _state = _ParseState.option;
            case _T.sb:
              _sub.clear();
              _state = _ParseState.sub;
            default:
              // NOP, GA, and the like carry nothing to show.
              _state = _ParseState.data;
          }
        case _ParseState.option:
          _negotiate(_verb, b);
          _state = _ParseState.data;
        case _ParseState.sub:
          if (b == _T.iac) {
            _state = _ParseState.subIac;
          } else {
            _sub.addByte(b);
          }
        case _ParseState.subIac:
          if (b == _T.se) {
            _subnegotiation(_sub.takeBytes());
            _state = _ParseState.data;
          } else {
            _sub.addByte(b);
            _state = _ParseState.sub;
          }
      }
    }
    if (text.length > 0 && !_output.isClosed) _output.add(text.takeBytes());
  }

  void _negotiate(int verb, int option) {
    switch (verb) {
      case _T.do_:
        final supported = option == _T.terminalType || option == _T.windowSize || option == _T.suppressGoAhead;
        if (supported) {
          if (_ours.add(option)) _send([_T.iac, _T.will, option]);
          if (option == _T.windowSize) _sendWindowSize();
        } else {
          _send([_T.iac, _T.wont, option]);
        }
      case _T.dont:
        if (_ours.remove(option)) _send([_T.iac, _T.wont, option]);
      case _T.will:
        final accepted = option == _T.echo || option == _T.suppressGoAhead;
        if (accepted) {
          if (_theirs.add(option)) _send([_T.iac, _T.do_, option]);
        } else {
          _send([_T.iac, _T.dont, option]);
        }
      case _T.wont:
        if (_theirs.remove(option)) _send([_T.iac, _T.dont, option]);
    }
  }

  void _subnegotiation(Uint8List data) {
    if (data.length >= 2 && data[0] == _T.terminalType && data[1] == _T.ttypeSend) {
      _send([_T.iac, _T.sb, _T.terminalType, _T.ttypeIs, ...ascii.encode(terminalType), _T.iac, _T.se]);
    }
  }

  void _sendWindowSize() {
    final bytes = <int>[];
    for (final v in [width >> 8, width & 0xff, height >> 8, height & 0xff]) {
      bytes.add(v);
      if (v == _T.iac) bytes.add(_T.iac);
    }
    _send([_T.iac, _T.sb, _T.windowSize, ...bytes, _T.iac, _T.se]);
  }
}

enum _ParseState { data, iac, option, sub, subIac }
