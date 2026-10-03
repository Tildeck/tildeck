import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../activity.dart';
import '../local/local_shell.dart';
import 'autocomplete.dart';
import 'file_browser.dart';
import 'serial.dart';
import 'ssh_connector.dart';
import 'telnet.dart';

enum SessionState { connecting, connected, closed }

/// One open tab: an SSH shell wired to a terminal emulator. The terminal
/// exists before the connection, so the tab can show progress and errors.
class TerminalSession extends ChangeNotifier {
  /// [scrollback] is how many lines stay above the screen.
  /// [openSerial] opens a serial target's port.
  TerminalSession(this.target, {int scrollback = 10000, this.openSerial = openSerialPort}) {
    terminal = Terminal(maxLines: scrollback);
    controller = TerminalController();
  }

  final ConnectionTarget target;
  final SerialOpener openSerial;
  late final Terminal terminal;
  late final TerminalController controller;

  SessionState state = SessionState.connecting;

  /// A name the user gave the tab; null shows the connection label.
  String? title;

  /// The server's own command history, for suggestions; read over a
  /// separate exec channel after connecting, and never stored.
  List<String> history = const [];

  /// Whether to read the history and follow typing for suggestions.
  bool autocomplete = true;

  /// The line being typed, followed in memory to filter suggestions.
  final line = LineTracker();

  /// The cursor's line asks for a password.
  bool atPasswordPrompt = false;

  void rename(String? name) {
    final trimmed = name?.trim();
    title = trimmed == null || trimmed.isEmpty ? null : trimmed;
    notifyListeners();
  }

  ConnectProblem? problem;

  /// The session reached the shell once: a later end is a drop, not a
  /// failure to connect.
  bool wasConnected = false;

  /// Which automatic reconnection this session is (0 for the first try).
  int reconnectAttempt = 0;

  SSHSession? _shell;

  /// The jump host [problem] happened at, when not the target itself.
  String? problemVia;

  SSHClient? _client;
  _Link? _link;
  final _subscriptions = <StreamSubscription<String>>[];

  /// Files and the server's history come over SSH only.
  bool get isSsh => target.protocol == ConnectionProtocol.ssh;

  /// Connects and opens an interactive shell sized to the terminal.
  Future<void> start(SshConnector connector, HostKeyPrompt promptHostKey) async {
    try {
      final link = switch (target.protocol) {
        ConnectionProtocol.ssh => await _openSsh(connector, promptHostKey),
        ConnectionProtocol.telnet => await _openTelnet(connector, promptHostKey),
        ConnectionProtocol.local => _openLocal(),
        ConnectionProtocol.serial => _openSerial(),
      };
      _link = link;

      // Streams can split a multi-byte character; the decoders keep the
      // partial bytes until the rest arrives.
      _subscriptions.add(
        link.output.transform(const Utf8Decoder(allowMalformed: true)).listen((data) {
          terminal.write(data);
          _checkPrompt();
        }),
      );
      terminal.onOutput = (data) {
        // Soft keyboard typing sends no key events: tell the idle lock.
        userActivity.ping();
        line.feed(data);
        if (autocomplete) notifyListeners();
        link.write(utf8.encode(applyCtrl(data)));
      };
      terminal.onResize = (width, height, pixelWidth, pixelHeight) =>
          link.resize(width, height, pixelWidth, pixelHeight);

      state = SessionState.connected;
      wasConnected = true;
      notifyListeners();
      final client = _client;
      if (autocomplete && client != null) unawaited(_loadHistory(client));
      final startup = target.startupCommand;
      if (startup != null && startup.trim().isNotEmpty) run(startup);

      await link.done;
      // A shell that ends without an exit status or signal did not exit:
      // the connection dropped.
      // A serial line ends on its own only when the device goes away.
      final shell = _shell;
      final dropped = shell != null
          ? shell.exitCode == null && shell.exitSignal == null
          : target.protocol == ConnectionProtocol.serial;
      _close(dropped ? ConnectProblem.disconnected : null);
    } on ConnectException catch (e) {
      problemVia = e.via;
      _close(e.problem);
    } catch (_) {
      _close(ConnectProblem.disconnected);
    }
  }

  Future<_Link> _openSsh(SshConnector connector, HostKeyPrompt promptHostKey) async {
    // The banner shows before the shell, as with OpenSSH.
    final client = await connector.connect(
      target,
      promptHostKey: promptHostKey,
      onBanner: (banner) => terminal.write(bannerText(banner)),
    );
    _client = client;
    final shell = _shell = await client.shell(
      pty: SSHPtyConfig(type: 'xterm-256color', width: terminal.viewWidth, height: terminal.viewHeight),
      environment: target.environment.isEmpty ? null : target.environment,
    );
    return _Link(
      output: shell.stdout.cast<List<int>>(),
      write: shell.write,
      resize: shell.resizeTerminal,
      done: shell.done,
      close: shell.close,
    );
  }

  _Link _openLocal() {
    final shell = target.localShell!;
    final Pty pty;
    try {
      pty = Pty.start(
        shell.executable,
        arguments: shell.arguments,
        // The whole environment: Windows shells need far more than the
        // few variables flutter_pty copies on its own.
        environment: Platform.environment,
        workingDirectory: localHome(),
        columns: terminal.viewWidth,
        rows: terminal.viewHeight,
      );
    } catch (_) {
      throw const ConnectException(ConnectProblem.localShellFailed);
    }
    return _Link(
      output: pty.output.cast<List<int>>(),
      write: pty.write,
      resize: (width, height, _, _) => pty.resize(height, width),
      done: pty.exitCode,
      close: pty.kill,
    );
  }

  _Link _openSerial() {
    final line = openSerial(target.host, target.port);
    return _Link(
      output: line.output.cast<List<int>>(),
      write: line.write,
      // A serial line has no window size to tell.
      resize: (_, _, _, _) {},
      done: line.done,
      close: line.close,
    );
  }

  Future<_Link> _openTelnet(SshConnector connector, HostKeyPrompt promptHostKey) async {
    final socket = await connector.openSocket(target, promptHostKey: promptHostKey);
    final telnet = TelnetChannel(socket, width: terminal.viewWidth, height: terminal.viewHeight);
    return _Link(
      output: telnet.output.cast<List<int>>(),
      write: telnet.write,
      resize: (width, height, _, _) => telnet.resize(width, height),
      done: telnet.done,
      close: telnet.close,
    );
  }

  /// An SFTP channel on this session's connection, for browsing files: no
  /// second sign-in.
  Future<SftpClient> openSftp() async {
    final client = _client;
    if (client == null || state != SessionState.connected) {
      throw const FileProblemException(FileProblem.disconnected);
    }
    return client.sftp();
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

  Future<void> _loadHistory(SSHClient client) async {
    try {
      final out = await client.run(historyCommand, stderr: false).timeout(const Duration(seconds: 8));
      history = parseHistory(utf8.decode(out, allowMalformed: true));
      notifyListeners();
    } catch (_) {
      // A server that refuses exec channels, or no history: no suggestions.
      history = const [];
    }
  }

  void _checkPrompt() {
    final buffer = terminal.buffer;
    final y = buffer.absoluteCursorY;
    final prompt = y < buffer.lines.length && isPasswordPrompt(buffer.lines[y].getText());
    if (prompt != atPasswordPrompt) {
      atPasswordPrompt = prompt;
      notifyListeners();
    }
  }

  /// Completes the typed line with [command], without running it.
  void complete(String command) {
    if (state != SessionState.connected) return;
    terminal.textInput(completionInput(line.line ?? '', command));
  }

  /// Answers a password prompt with the password this session signed in
  /// with.
  void fillPassword() {
    final password = target.password;
    if (state != SessionState.connected || password == null || !atPasswordPrompt) return;
    terminal.textInput('$password\r');
    atPasswordPrompt = false;
    notifyListeners();
  }

  /// Runs a snippet: each line is sent as typed and followed by Enter.
  void run(String command) {
    if (state != SessionState.connected) return;
    final lines = command.replaceAll('\r\n', '\n').split('\n');
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    if (lines.isEmpty) return;
    terminal.textInput('${lines.join('\r')}\r');
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
    // Closed here on purpose: not a drop.
    _shell = null;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _link?.close();
    _client?.close();
    _close(null);
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

/// What a session types into and reads from, whatever carries it.
class _Link {
  const _Link({
    required this.output,
    required this.write,
    required this.resize,
    required this.done,
    required this.close,
  });

  final Stream<List<int>> output;
  final void Function(Uint8List data) write;
  final void Function(int width, int height, int pixelWidth, int pixelHeight) resize;
  final Future<void> done;
  final void Function() close;
}
