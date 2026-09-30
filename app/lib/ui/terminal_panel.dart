import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../l10n/app_localizations.dart';
import '../ssh/ssh_connector.dart';
import '../ssh/terminal_session.dart';
import '../theme.dart';

/// The terminal of one session. Terminal content is always left to right,
/// whatever the interface language.
class TerminalPanel extends StatelessWidget {
  const TerminalPanel({super.key, required this.session, required this.showKeyBar, required this.onReconnect});

  final TerminalSession session;

  /// The on-screen key bar for touch devices, whose keyboards have no Esc,
  /// Tab, Ctrl, or arrow keys.
  final bool showKeyBar;
  final VoidCallback onReconnect;

  static const _theme = TerminalTheme(
    cursor: Color(0xFF5EEAD4),
    selection: Color(0x805EEAD4),
    foreground: Color(0xFFE7F4F2),
    background: Color(0xFF0B181B),
    black: Color(0xFF1B2B2F),
    red: Color(0xFFF87171),
    green: Color(0xFF4ADE80),
    yellow: Color(0xFFFBBF24),
    blue: Color(0xFF60A5FA),
    magenta: Color(0xFFF472B6),
    cyan: Color(0xFF2DD4BF),
    white: Color(0xFFD5E3E1),
    brightBlack: Color(0xFF5B7075),
    brightRed: Color(0xFFFCA5A5),
    brightGreen: Color(0xFF86EFAC),
    brightYellow: Color(0xFFFDE68A),
    brightBlue: Color(0xFF93C5FD),
    brightMagenta: Color(0xFFF9A8D4),
    brightCyan: Color(0xFF5EEAD4),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFBBF24),
    searchHitBackgroundCurrent: Color(0xFF2DD4BF),
    searchHitForeground: Color(0xFF0B181B),
  );

  Future<void> _copy(BuildContext context) async {
    final text = session.selectedText;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    session.controller.clearSelection();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).copied), duration: const Duration(seconds: 1)),
      );
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text case final text?) session.paste(text);
  }

  @override
  Widget build(BuildContext context) {
    // The interface direction, read before the terminal forces LTR, for the
    // parts that speak the interface language.
    final appDirection = Directionality.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final view = CallbackShortcuts(
          // The desktop terminal convention: Ctrl+C and Ctrl+V belong to the
          // remote program, so copy and paste add Shift.
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true): () => _copy(context),
            const SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true): _paste,
          },
          child: TerminalView(
            session.terminal,
            controller: session.controller,
            theme: _theme,
            textStyle: const TerminalStyle(fontFamily: 'JetBrainsMono', fontSize: 14),
            padding: const EdgeInsets.all(8),
            autofocus: true,
            // Right click copies a selection, or pastes when nothing is
            // selected, as in the Windows console.
            onSecondaryTapDown: (_, _) => session.selectedText?.isNotEmpty == true ? _copy(context) : _paste(),
          ),
        );

        return Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: _theme.background,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: view),
                      if (session.state != SessionState.connected)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Directionality(
                            textDirection: appDirection,
                            child: _StatusBanner(session: session, onReconnect: onReconnect),
                          ),
                        ),
                    ],
                  ),
                ),
                if (showKeyBar && session.state == SessionState.connected)
                  KeyBar(session: session, onCopy: () => _copy(context), onPaste: _paste),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.session, required this.onReconnect});

  final TerminalSession session;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final connecting = session.state == SessionState.connecting;
    final message = connecting
        ? t.connectingTo(session.target.label)
        : switch (session.problem) {
            null => t.disconnected,
            ConnectProblem.unreachable => t.errConnUnreachable,
            ConnectProblem.timeout => t.errConnTimeout,
            ConnectProblem.authFailed => t.errConnAuthFailed,
            ConnectProblem.hostKeyRejected => t.errConnHostKeyRejected,
            ConnectProblem.keyInvalid => t.errConnKeyInvalid,
            ConnectProblem.keyPassphraseRequired => t.errConnKeyPassphraseRequired,
            ConnectProblem.keyPassphraseWrong => t.errConnKeyPassphraseWrong,
            ConnectProblem.disconnected => t.errConnDisconnected,
          };

    return Material(
      color: c.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            if (connecting)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
            else
              Icon(
                session.problem == null ? Icons.link_off : Icons.error_outline,
                color: session.problem == null ? c.muted : c.danger,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: TextStyle(color: c.ink)),
            ),
            if (!connecting) TextButton(onPressed: onReconnect, child: Text(t.reconnect)),
          ],
        ),
      ),
    );
  }
}

/// Esc, Tab, Ctrl, arrows, and the symbols a phone keyboard hides.
class KeyBar extends StatelessWidget {
  const KeyBar({super.key, required this.session, required this.onCopy, required this.onPaste});

  final TerminalSession session;
  final VoidCallback onCopy;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final terminal = session.terminal;

    Widget key(String label, VoidCallback onTap, {bool on = false, Key? id}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: on ? const Color(0xFF2DD4BF) : const Color(0xFF1B2B2F),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: id,
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 44),
            height: 40,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: on ? const Color(0xFF061A1A) : const Color(0xFFE7F4F2),
              ),
            ),
          ),
        ),
      ),
    );

    void send(TerminalKey k) {
      terminal.keyInput(k, ctrl: session.ctrlLatched);
      if (session.ctrlLatched) session.toggleCtrl();
    }

    return Container(
      color: const Color(0xFF0F2226),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            key('Esc', () => send(TerminalKey.escape), id: const ValueKey('key-esc')),
            key('Tab', () => send(TerminalKey.tab), id: const ValueKey('key-tab')),
            key('Ctrl', session.toggleCtrl, on: session.ctrlLatched, id: const ValueKey('key-ctrl')),
            key('←', () => send(TerminalKey.arrowLeft)),
            key('↑', () => send(TerminalKey.arrowUp)),
            key('↓', () => send(TerminalKey.arrowDown)),
            key('→', () => send(TerminalKey.arrowRight)),
            for (final symbol in ['|', '~', '/', '-', '_', r'$']) key(symbol, () => terminal.textInput(symbol)),
            key(t.copy, onCopy),
            key(t.paste, onPaste),
          ],
        ),
      ),
    );
  }
}
