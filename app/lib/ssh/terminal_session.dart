import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import 'ssh_connector.dart';

enum SessionState { connecting, connected, closed }

/// One open tab: an SSH shell wired to a terminal emulator. The terminal
/// exists before the connection, so the tab can show progress and errors.
class TerminalSession extends ChangeNotifier {
  TerminalSession(this.target) {
    terminal = Terminal(maxLines: 10000);
    controller = TerminalController();
  }

  final ConnectionTarget target;
  late final Terminal terminal;
  late final TerminalController controller;

  SessionState state = SessionState.connecting;
  ConnectProblem? problem;

  SSHClient? _client;
  SSHSession? _shell;
  final _subscriptions = <StreamSubscription<String>>[];

  /// Connects and opens an interactive shell sized to the terminal.
  Future<void> start(SshConnector connector, HostKeyPrompt promptHostKey) async {
    try {
      final client = await connector.connect(target, promptHostKey: promptHostKey);
      _client = client;
      final shell = await client.shell(
        pty: SSHPtyConfig(type: 'xterm-256color', width: terminal.viewWidth, height: terminal.viewHeight),
      );
      _shell = shell;

      // Streams can split a multi-byte character; the decoders keep the
      // partial bytes until the rest arrives.
      _subscriptions.add(
        shell.stdout.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen(terminal.write),
      );
      terminal.onOutput = (data) => shell.write(utf8.encode(applyCtrl(data)));
      terminal.onResize = (width, height, pixelWidth, pixelHeight) =>
          shell.resizeTerminal(width, height, pixelWidth, pixelHeight);

      state = SessionState.connected;
      notifyListeners();

      await shell.done;
      _close(null);
    } on ConnectException catch (e) {
      _close(e.problem);
    } catch (_) {
      _close(ConnectProblem.disconnected);
    }
  }

  /// Ctrl from the on-screen key bar: it applies to the next character typed
  /// on the soft keyboard, which has no Ctrl key of its own.
  bool ctrlLatched = false;

  void toggleCtrl() {
    ctrlLatched = !ctrlLatched;
    notifyListeners();
  }

  @visibleForTesting
  String applyCtrl(String data) {
    if (!ctrlLatched || data.length != 1) return data;
    ctrlLatched = false;
    notifyListeners();
    final code = data.toUpperCase().codeUnitAt(0);
    // Ctrl+A to Ctrl+Z and Ctrl+[ \ ] ^ _ are the ASCII control codes 1 to 31.
    return code >= 0x40 && code <= 0x5f ? String.fromCharCode(code & 0x1f) : data;
  }

  /// Text typed or pasted by the user, sent as if from the keyboard.
  void paste(String text) {
    if (state == SessionState.connected) terminal.paste(text);
  }

  /// The selected text, for copying.
  String? get selectedText {
    final selection = controller.selection;
    return selection == null ? null : terminal.buffer.getText(selection);
  }

  void _close(ConnectProblem? why) {
    if (state == SessionState.closed) return;
    problem = why;
    state = SessionState.closed;
    terminal.onOutput = null;
    terminal.onResize = null;
    notifyListeners();
  }

  /// Ends the session and releases the connection.
  void disconnect() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _shell?.close();
    _client?.close();
    _close(null);
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
