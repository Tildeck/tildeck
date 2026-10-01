import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/telnet.dart';

const iac = 255, dont = 254, do_ = 253, wont = 252, will = 251, sb = 250, se = 240;
const echo = 1, sga = 3, ttype = 24, naws = 31;

/// A server side that records what the client sends.
class Peer {
  Peer._(this.server);
  final ServerSocket server;
  late Socket socket;
  final received = <int>[];

  static Future<(Peer, TelnetChannel)> start({int width = 80, int height = 24}) async {
    final peer = Peer._(await ServerSocket.bind('127.0.0.1', 0));
    final accepted = peer.server.first;
    final channel = TelnetChannel(await SSHSocket.connect('127.0.0.1', peer.server.port), width: width, height: height);
    peer.socket = await accepted;
    peer.socket.listen(peer.received.addAll);
    return (peer, channel);
  }

  Future<void> expectReceived(List<int> bytes) async {
    for (var i = 0; i < 100 && !_contains(bytes); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(_contains(bytes), isTrue, reason: 'expected $bytes in $received');
  }

  bool _contains(List<int> bytes) {
    for (var i = 0; i + bytes.length <= received.length; i++) {
      var match = true;
      for (var j = 0; j < bytes.length && match; j++) {
        match = received[i + j] == bytes[j];
      }
      if (match) return true;
    }
    return false;
  }

  Future<void> close() async {
    socket.destroy();
    await server.close();
  }
}

void main() {
  test('answers the options it supports and refuses the rest', () async {
    final (peer, channel) = await Peer.start(width: 120, height: 40);
    addTearDown(peer.close);
    addTearDown(channel.close);
    peer.socket.add([iac, do_, ttype, iac, do_, naws, iac, will, echo, iac, will, sga, iac, do_, 99, iac, will, 98]);
    await peer.expectReceived([iac, will, ttype]);
    await peer.expectReceived([iac, will, naws, iac, sb, naws, 0, 120, 0, 40, iac, se]);
    await peer.expectReceived([iac, do_, echo]);
    await peer.expectReceived([iac, do_, sga]);
    await peer.expectReceived([iac, wont, 99]);
    await peer.expectReceived([iac, dont, 98]);

    // Asked again, it does not answer again: no negotiation loops.
    final before = peer.received.length;
    peer.socket.add([iac, will, echo, iac, do_, ttype]);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(peer.received.length, before);

    peer.socket.add([iac, sb, ttype, 1, iac, se]);
    await peer.expectReceived([iac, sb, ttype, 0, ...ascii.encode('XTERM-256COLOR'), iac, se]);

    channel.resize(100, 255);
    await peer.expectReceived([iac, sb, naws, 0, 100, 0, 255, 255, iac, se]);
  });

  test('the negotiation is not shown, a doubled 255 is, and a command may arrive split', () async {
    final (peer, channel) = await Peer.start();
    addTearDown(peer.close);
    addTearDown(channel.close);
    final shown = <int>[];
    channel.output.listen(shown.addAll);
    peer.socket.add([...ascii.encode('log'), iac]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    peer.socket.add([will, echo, ...ascii.encode('in: '), iac, iac, iac, sb, ttype]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    peer.socket.add([1, iac, se, ...ascii.encode('!')]);
    await peer.expectReceived([iac, do_, echo]);
    await peer.expectReceived([iac, sb, ttype, 0]);
    expect(shown, [...ascii.encode('login: '), 255, ...ascii.encode('!')]);
  });

  test('what is typed has 255 doubled and a bare CR followed by NUL', () async {
    final (peer, channel) = await Peer.start();
    addTearDown(peer.close);
    addTearDown(channel.close);
    channel.write([...ascii.encode('ls'), 13, 255, 13, 10]);
    await peer.expectReceived([...ascii.encode('ls'), 13, 0, 255, 255, 13, 10]);
  });

  test('the end of the connection completes done', () async {
    final (peer, channel) = await Peer.start();
    await peer.close();
    await channel.done.timeout(const Duration(seconds: 5));
  });
}
