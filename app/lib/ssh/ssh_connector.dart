import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../local/local_shell.dart';
import 'certificates.dart';
import 'known_hosts.dart';
import 'proxy.dart';

enum ConnectionProtocol { ssh, telnet, local, serial }

/// The usual speed of a serial console.
const defaultBaudRate = 115200;

/// How a session's bytes become text. Old devices and consoles often speak
/// ISO-8859-1 (Latin-1) rather than UTF-8.
enum TerminalCharset { utf8, latin1 }

/// The terminal type a session announces when the host sets none.
const defaultTerminalType = 'xterm-256color';

/// Where to connect and how to authenticate.
class ConnectionTarget {
  const ConnectionTarget({
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKey,
    this.passphrase,
    this.certificate,
    this.startupCommand,
    this.environment = const {},
    this.hostId,
    this.jump,
    this.agentKeys,
    this.proxy,
    this.protocol = ConnectionProtocol.ssh,
    this.localShell,
    this.localName,
    this.terminalType = defaultTerminalType,
    this.charset = TerminalCharset.utf8,
  });

  /// A local terminal: [host] and [username] are unused.
  const ConnectionTarget.local(LocalShell shell, String name)
    : this(host: 'localhost', username: '', protocol: ConnectionProtocol.local, localShell: shell, localName: name);

  final String host;
  final int port;
  final String username;
  final String? password;

  /// A private key in PEM or OpenSSH format.
  final String? privateKey;
  final String? passphrase;

  /// An OpenSSH certificate for [privateKey]: signs in with it first.
  final String? certificate;

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

  /// Telnet has no sign-in of its own: the server asks in the terminal,
  /// and [password] is offered at its prompt.
  final ConnectionProtocol protocol;

  /// The shell a local terminal runs, and its name for the tab.
  final LocalShell? localShell;
  final String? localName;

  /// What the session tells the server it is (TERM).
  final String terminalType;
  final TerminalCharset charset;

  String get label {
    if (protocol == ConnectionProtocol.local) return localName ?? localShell?.executable ?? '';
    if (protocol == ConnectionProtocol.serial) return port == defaultBaudRate ? host : '$host $port';
    final defaultPort = protocol == ConnectionProtocol.telnet ? 23 : 22;
    final address = port == defaultPort ? host : '$host:$port';
    return username.isEmpty ? address : '$username@$address';
  }

  /// The same target with another command to run once the shell opens.
  ConnectionTarget withStartupCommand(String? command) => ConnectionTarget(
    host: host,
    port: port,
    username: username,
    password: password,
    privateKey: privateKey,
    passphrase: passphrase,
    certificate: certificate,
    startupCommand: command,
    environment: environment,
    hostId: hostId,
    jump: jump,
    agentKeys: agentKeys,
    proxy: proxy,
    protocol: protocol,
    localShell: localShell,
    localName: localName,
    terminalType: terminalType,
    charset: charset,
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

  /// A local terminal's shell could not start.
  localShellFailed,

  /// A serial port could not open: missing, or in use.
  serialFailed,
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

/// Asks the user for what a server's keyboard-interactive sign-in wants
/// beyond the saved password: a one-time code, say. Returns one answer per
/// prompt, or null when the user cancels.
typedef LoginPrompt =
    Future<List<String>?> Function({
      required ConnectionTarget target,
      required String name,
      required String instruction,
      required List<SSHUserInfoPrompt> prompts,
    });

/// Opens SSH connections with host key verification against [knownHosts].
class SshConnector {
  SshConnector({required this.knownHosts, this.timeout = const Duration(seconds: 15)});

  final KnownHosts knownHosts;
  final Duration timeout;

  /// Shows a keyboard-interactive server's questions to the user; set by
  /// the screen that opens connections. Without it, only the saved password
  /// answers them.
  LoginPrompt? askLogin;

  /// The answers to a keyboard-interactive request: the saved [password]
  /// for the first prompt that asks for a password (once per connection,
  /// so a wrong one is not sent again), and the user's answers, through
  /// [ask], for the rest. Null when someone must answer and nobody can, or
  /// the user cancels: the server then moves on or refuses.
  static Future<List<String>?> answerLogin(
    SSHUserInfoRequest request, {
    required String? password,
    required bool passwordUsed,
    required void Function() onPasswordUsed,
    Future<List<String>?> Function(List<SSHUserInfoPrompt> prompts)? ask,
  }) async {
    final answers = List<String?>.filled(request.prompts.length, null);
    var used = passwordUsed;
    for (final (i, prompt) in request.prompts.indexed) {
      if (password != null && !used && !prompt.echo && isPasswordPrompt(prompt.promptText)) {
        answers[i] = password;
        used = true;
        onPasswordUsed();
      }
    }
    final open = [
      for (final (i, answer) in answers.indexed)
        if (answer == null) i,
    ];
    if (open.isNotEmpty) {
      if (ask == null) return null;
      final typed = await ask([for (final i in open) request.prompts[i]]);
      if (typed == null || typed.length != open.length) return null;
      for (final (j, i) in open.indexed) {
        answers[i] = typed[j];
      }
    }
    return answers.cast<String>();
  }

  /// "Password:", "user@host's password:", "Passcode", not "Verification
  /// code:" or "One-time password:".
  static bool isPasswordPrompt(String text) {
    final t = text.toLowerCase();
    if (RegExp(r'one[- ]?time|verification|otp|token|authenticator|2fa|duo').hasMatch(t)) return false;
    return RegExp(r'pass(word|phrase|code)?').hasMatch(t);
  }

  /// [onBanner] is told the target's sign-in banner, if it sends one.
  Future<SSHClient> connect(
    ConnectionTarget target, {
    required HostKeyPrompt promptHostKey,
    void Function(String banner)? onBanner,
  }) => _throughJump(target, promptHostKey, (via) => _connect(target, promptHostKey, via, onBanner), (c) => c.done);

  /// A plain connection to the target's port, through its jump hosts or
  /// proxy like an SSH one: for protocols other than SSH.
  Future<SSHSocket> openSocket(ConnectionTarget target, {required HostKeyPrompt promptHostKey}) =>
      _throughJump(target, promptHostKey, (via) => _socketFor(target, via), (s) => s.done);

  /// Opens [open] directly, or inside a connection to the target's jump
  /// host, which then lives as long as what was opened ([doneOf]).
  Future<T> _throughJump<T>(
    ConnectionTarget target,
    HostKeyPrompt promptHostKey,
    Future<T> Function(SSHClient? via) open,
    Future<void> Function(T) doneOf,
  ) async {
    final jump = target.jump;
    if (jump == null) return open(null);
    final SSHClient via;
    try {
      via = await connect(jump, promptHostKey: promptHostKey);
    } on ConnectException catch (e) {
      throw ConnectException(e.problem, e.detail, e.via ?? jump.label);
    }
    try {
      final opened = await open(via);
      unawaited(doneOf(opened).catchError((_) {}).whenComplete(via.close));
      return opened;
    } catch (_) {
      via.close();
      rethrow;
    }
  }

  Future<SSHClient> _connect(
    ConnectionTarget target,
    HostKeyPrompt promptHostKey,
    SSHClient? via,
    void Function(String banner)? onBanner,
  ) async {
    final identities = _identities(target);
    final socket = await _socketFor(target, via);
    return _handshake(target, promptHostKey, identities, socket, onBanner);
  }

  Future<SSHSocket> _socketFor(ConnectionTarget target, SSHClient? via) async {
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
    return socket;
  }

  Future<SSHClient> _handshake(
    ConnectionTarget target,
    HostKeyPrompt promptHostKey,
    List<SSHIdentity>? identities,
    SSHSocket socket,
    void Function(String banner)? onBanner,
  ) async {
    var hostKeyRejected = false;
    var passwordUsed = false;
    final client = SSHClient(
      socket,
      username: target.username,
      identities: identities,
      onUserauthBanner: onBanner,
      onPasswordRequest: target.password == null ? null : () => target.password,
      // Keyboard-interactive servers ask for the password this way, and for
      // anything else they want (a one-time code), which the user answers.
      onUserInfoRequest: target.password == null && askLogin == null
          ? null
          : (request) => answerLogin(
              request,
              password: target.password,
              passwordUsed: passwordUsed,
              onPasswordUsed: () => passwordUsed = true,
              ask: askLogin == null
                  ? null
                  : (prompts) => askLogin!(
                      target: target,
                      name: request.name,
                      instruction: request.instruction,
                      prompts: prompts,
                    ),
            ),
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

  /// The key, after its certificate when it has one: a server that does
  /// not trust the certificate's authority may still accept the key.
  static List<SSHIdentity>? _identities(ConnectionTarget target) {
    final pairs = _keyPairs(target);
    if (pairs == null) return null;
    final certificate = target.certificate == null ? null : readCertificate(target.certificate!);
    return [if (certificate != null) certificateIdentity(certificate, pairs.first), ...pairs];
  }

  static List<SSHKeyPair>? _keyPairs(ConnectionTarget target) {
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

/// CSI (7-bit and the C1 form), OSC ended by BEL or ST, and two-character
/// escape sequences.
final _bannerEscapes = RegExp(r'(?:\x1b\[|\x9b)[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?|\x1b[ -/]*[0-~]');

/// A server's sign-in banner made safe to show in a terminal: its own text
/// and line breaks only, so it cannot move the cursor, change colors, or
/// send the terminal commands, as OpenSSH does.
String bannerText(String banner) {
  // Whole escape sequences go first, so none leaves its tail as text; then
  // every control character left.
  final plain = banner.replaceAll(_bannerEscapes, '').replaceAll('\r\n', '\n');
  final text = String.fromCharCodes([
    for (final rune in plain.runes)
      if (rune == 0x0a || rune == 0x09 || (rune >= 0x20 && rune != 0x7f && (rune < 0x80 || rune > 0x9f))) rune,
  ]).trimRight();
  return text.isEmpty ? '' : '${text.replaceAll('\n', '\r\n')}\r\n';
}
