import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../l10n/app_localizations.dart';
import '../ssh/autocomplete.dart';
import '../ssh/ssh_connector.dart';
import '../ssh/terminal_session.dart';
import '../terminal/keyword_highlighter.dart';
import '../terminal/terminal_options.dart';
import '../terminal/terminal_themes.dart';
import '../theme.dart';

/// The terminal of one session. Terminal content is always left to right,
/// whatever the interface language.
class TerminalPanel extends StatefulWidget {
  TerminalPanel({
    super.key,
    required this.session,
    required this.showKeyBar,
    required this.onReconnect,
    TerminalTheme? theme,
    this.fontSize = defaultFontSize,
    this.onFontSize,
    this.snippets = const {},
    this.options = const TerminalOptions(),
    this.onAutoReconnect,
  }) : theme = theme ?? terminalThemes.first.theme;

  final TerminalSession session;

  /// The on-screen key bar for touch devices, whose keyboards have no Esc,
  /// Tab, Ctrl, or arrow keys.
  final bool showKeyBar;
  final VoidCallback onReconnect;
  final TerminalTheme theme;
  final double fontSize;

  /// Ctrl and + or - (or 0, back to the default) asks for another size.
  final ValueChanged<double>? onFontSize;

  /// Snippet names and commands, offered among the suggestions.
  final Map<String, String> snippets;

  /// Font, line height, cursor, bell, and copying on selection.
  final TerminalOptions options;

  /// Reconnects on its own after a drop: the attempt number. Null never.
  final ValueChanged<int>? onAutoReconnect;

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

/// One search hit: a line of the buffer and the columns it spans.
typedef _Hit = ({int line, int start, int end});

class _TerminalPanelState extends State<TerminalPanel> {
  TerminalSession get session => widget.session;

  final _scroll = ScrollController();
  final _searchField = TextEditingController();
  final _searchFocus = FocusNode();
  final _terminalFocus = FocusNode();
  bool _searching = false;
  List<_Hit> _hits = const [];
  int _current = -1;
  final _highlights = <TerminalHighlight>[];

  static const _maxHits = 500;

  /// The screen flashes for a moment at a bell, when the bell is visual.
  bool _flash = false;
  Timer? _flashTimer;
  Timer? _copyTimer;
  String? _copied;

  @override
  void initState() {
    super.initState();
    session.terminal.onBell = _bell;
    session.controller.addListener(_selectionChanged);
    session.addListener(_maybeReconnect);
    final keywords = widget.options.keywords;
    if (keywords != null) _keywords = KeywordHighlighter(session.terminal, session.controller, keywords)..scan();
    // A session that dropped before this panel was built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeReconnect();
    });
  }

  KeywordHighlighter? _keywords;
  Timer? _reconnectTimer;
  int _reconnectIn = 0;

  /// The attempt a reconnection now would be: after a drop from a working
  /// session, the first; after a failed attempt, the next.
  int get _nextAttempt => session.wasConnected ? 1 : session.reconnectAttempt + 1;

  /// A dropped connection (or a failed attempt to bring it back) tries
  /// again after a wait, a few times, unless the user said no.
  void _maybeReconnect() {
    final retry = widget.onAutoReconnect;
    if (retry == null || !widget.options.autoReconnect || _reconnectTimer != null) return;
    if (session.state != SessionState.closed) return;
    final again = session.wasConnected || session.reconnectAttempt > 0;
    final problem = session.problem;
    final transient =
        problem == ConnectProblem.disconnected ||
        problem == ConnectProblem.unreachable ||
        problem == ConnectProblem.timeout;
    final attempt = _nextAttempt;
    if (!again || !transient || attempt > reconnectDelays.length) return;
    _reconnectIn = reconnectDelays[attempt - 1].inSeconds;
    _reconnectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (--_reconnectIn <= 0) {
        timer.cancel();
        retry(attempt);
      } else {
        setState(() {});
      }
    });
    setState(() {});
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    setState(() => _reconnectIn = -1);
  }

  void _bell() {
    switch (widget.options.bell) {
      case BellMode.none:
        return;
      case BellMode.sound:
        SystemSound.play(SystemSoundType.alert);
      case BellMode.visual:
        if (!mounted) return;
        setState(() => _flash = true);
        _flashTimer?.cancel();
        _flashTimer = Timer(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _flash = false);
        });
    }
  }

  /// With copying on selection, a selection is copied once it stops
  /// changing: dragging changes it many times.
  void _selectionChanged() {
    if (!widget.options.copyOnSelect) return;
    _copyTimer?.cancel();
    _copyTimer = Timer(const Duration(milliseconds: 300), () {
      final text = session.selectedText;
      if (text == null || text.isEmpty || text == _copied) return;
      _copied = text;
      Clipboard.setData(ClipboardData(text: text));
    });
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _keywords?.dispose();
    session.removeListener(_maybeReconnect);
    _flashTimer?.cancel();
    _copyTimer?.cancel();
    session.controller.removeListener(_selectionChanged);
    if (session.terminal.onBell == _bell) session.terminal.onBell = null;
    _clearHighlights();
    _scroll.dispose();
    _searchField.dispose();
    _searchFocus.dispose();
    _terminalFocus.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    final text = session.selectedText;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    session.controller.clearSelection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).copied), duration: const Duration(seconds: 1)),
      );
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text case final text?) session.paste(text);
  }

  void _size(double size) => widget.onFontSize?.call(size.clamp(minFontSize, maxFontSize));

  void _openSearch() {
    setState(() => _searching = true);
    _searchFocus.requestFocus();
    _searchField.selection = TextSelection(baseOffset: 0, extentOffset: _searchField.text.length);
  }

  void _closeSearch() {
    _clearHighlights();
    setState(() {
      _searching = false;
      _hits = const [];
      _current = -1;
    });
    _terminalFocus.requestFocus();
  }

  void _clearHighlights() {
    for (final h in _highlights) {
      h.dispose();
    }
    _highlights.clear();
  }

  /// Finds every occurrence of the query in the buffer, case-insensitive,
  /// and highlights them; the last (newest) one is current.
  void _search(String query) {
    final hits = <_Hit>[];
    final needle = query.toLowerCase();
    if (needle.isNotEmpty) {
      final lines = session.terminal.buffer.lines;
      for (var i = 0; i < lines.length && hits.length < _maxHits; i++) {
        final text = lines[i].getText().toLowerCase();
        for (var at = text.indexOf(needle); at >= 0 && hits.length < _maxHits; at = text.indexOf(needle, at + 1)) {
          hits.add((line: i, start: at, end: at + needle.length));
        }
      }
    }
    setState(() {
      _hits = hits;
      _current = hits.isEmpty ? -1 : hits.length - 1;
    });
    _paintHits();
  }

  void _paintHits() {
    _clearHighlights();
    final buffer = session.terminal.buffer;
    for (final (i, hit) in _hits.indexed) {
      _highlights.add(
        session.controller.highlight(
          p1: buffer.createAnchor(hit.start, hit.line),
          p2: buffer.createAnchor(hit.end, hit.line),
          // Translucent, so the matched text stays readable.
          color: (i == _current ? widget.theme.searchHitBackgroundCurrent : widget.theme.searchHitBackground)
              .withValues(alpha: 0.45),
        ),
      );
    }
    if (_current >= 0) _reveal(_hits[_current].line);
  }

  /// Scrolls so [line] shows, about a third from the top.
  void _reveal(int line) {
    if (!_scroll.hasClients) return;
    final lineHeight = widget.fontSize * 1.2;
    final top = (line - session.terminal.viewHeight ~/ 3) * lineHeight;
    _scroll.jumpTo(top.clamp(0.0, _scroll.position.maxScrollExtent));
  }

  void _step(int by) {
    if (_hits.isEmpty) return;
    setState(() => _current = (_current + by) % _hits.length);
    _paintHits();
  }

  @override
  Widget build(BuildContext context) {
    // The interface direction, read before the terminal forces LTR, for the
    // parts that speak the interface language.
    final appDirection = Directionality.of(context);
    final t = AppLocalizations.of(context);
    final theme = widget.theme;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final view = CallbackShortcuts(
          // The desktop terminal convention: Ctrl+C and Ctrl+V belong to the
          // remote program, so copy and paste add Shift.
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true): _copy,
            const SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true): _paste,
            const SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true): _openSearch,
            const SingleActivator(LogicalKeyboardKey.equal, control: true): () => _size(widget.fontSize + 1),
            const SingleActivator(LogicalKeyboardKey.equal, control: true, shift: true): () =>
                _size(widget.fontSize + 1),
            const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): () => _size(widget.fontSize + 1),
            const SingleActivator(LogicalKeyboardKey.minus, control: true): () => _size(widget.fontSize - 1),
            const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true): () => _size(widget.fontSize - 1),
            const SingleActivator(LogicalKeyboardKey.digit0, control: true): () => _size(defaultFontSize),
          },
          child: Stack(
            children: [
              TerminalView(
                session.terminal,
                controller: session.controller,
                scrollController: _scroll,
                focusNode: _terminalFocus,
                theme: theme,
                textStyle: TerminalStyle(
                  fontFamily: widget.options.fontFamily,
                  fontFamilyFallback: [...widget.options.fontFallback, ...const TerminalStyle().fontFamilyFallback],
                  fontSize: widget.fontSize,
                  height: widget.options.lineHeight,
                ),
                cursorType: widget.options.cursor,
                padding: const EdgeInsets.all(8),
                autofocus: true,
                // Right click copies a selection, or pastes when nothing is
                // selected, as in the Windows console.
                onSecondaryTapDown: (_, _) => session.selectedText?.isNotEmpty == true ? _copy() : _paste(),
              ),
              // A visual bell: the screen lights up for a moment.
              if (_flash)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      key: const ValueKey('bellFlash'),
                      color: theme.foreground.withValues(alpha: 0.12),
                    ),
                  ),
                ),
            ],
          ),
        );

        return Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: theme.background,
            child: Column(
              children: [
                if (_searching)
                  Directionality(
                    textDirection: appDirection,
                    child: _SearchBar(
                      field: _searchField,
                      focus: _searchFocus,
                      count: _hits.isEmpty
                          ? (_searchField.text.isEmpty ? '' : t.noMatches)
                          : t.matchOf(_current + 1, _hits.length),
                      onChanged: _search,
                      onNext: () => _step(1),
                      onPrevious: () => _step(-1),
                      onClose: _closeSearch,
                    ),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: view),
                      if (!_searching && session.state == SessionState.connected)
                        Positioned(
                          top: 6,
                          right: 10,
                          child: IconButton.filledTonal(
                            key: const ValueKey('terminalSearch'),
                            tooltip: t.searchTerminal,
                            visualDensity: VisualDensity.compact,
                            iconSize: 18,
                            onPressed: _openSearch,
                            icon: const Icon(Icons.search_rounded),
                          ),
                        ),
                      if (session.state != SessionState.connected)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Directionality(
                            textDirection: appDirection,
                            child: _StatusBanner(
                              session: session,
                              onReconnect: widget.onReconnect,
                              reconnectIn: _reconnectTimer?.isActive == true ? _reconnectIn : null,
                              attempt: _nextAttempt,
                              onCancel: _cancelReconnect,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (session.state == SessionState.connected && session.autocomplete)
                  Directionality(
                    textDirection: appDirection,
                    child: _SuggestionBar(session: session, snippets: widget.snippets),
                  ),
                if (widget.showKeyBar && session.state == SessionState.connected)
                  KeyBar(session: session, onCopy: _copy, onPaste: _paste),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Suggestions for the line being typed: commands from the server's
/// history and snippets, or the saved password at a password prompt. A tap
/// completes the line; the user still presses Enter.
class _SuggestionBar extends StatelessWidget {
  const _SuggestionBar({required this.session, required this.snippets});

  final TerminalSession session;
  final Map<String, String> snippets;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final canFill = session.atPasswordPrompt && session.target.password != null;
    final typed = session.line.line;
    final suggestions = canFill || typed == null
        ? const <Suggestion>[]
        : suggest(typed, session.history, snippets: snippets);
    if (!canFill && suggestions.isEmpty) return const SizedBox.shrink();
    return Material(
      color: c.surface,
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          children: [
            if (canFill)
              ActionChip(
                key: const ValueKey('fillPassword'),
                avatar: Icon(Icons.key_rounded, size: 16, color: c.brand),
                label: Text(t.fillPassword),
                onPressed: session.fillPassword,
              ),
            for (final (i, s) in suggestions.indexed)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ActionChip(
                  key: ValueKey('suggestion-$i'),
                  avatar: Icon(s.snippetName == null ? Icons.history_rounded : Icons.code_rounded, size: 16),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      s.command,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13),
                    ),
                  ),
                  onPressed: () => session.complete(s.command),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.field,
    required this.focus,
    required this.count,
    required this.onChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
  });

  final TextEditingController field;
  final FocusNode focus;
  final String count;
  final ValueChanged<String> onChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return Material(
      color: c.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): onClose,
            const SingleActivator(LogicalKeyboardKey.enter): onNext,
            const SingleActivator(LogicalKeyboardKey.enter, shift: true): onPrevious,
          },
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('terminalSearchField'),
                  controller: field,
                  focusNode: focus,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: t.searchTerminal,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                count,
                key: const ValueKey('terminalSearchCount'),
                style: TextStyle(color: c.muted),
              ),
              IconButton(tooltip: t.previousMatch, onPressed: onPrevious, icon: const Icon(Icons.keyboard_arrow_up)),
              IconButton(tooltip: t.nextMatch, onPressed: onNext, icon: const Icon(Icons.keyboard_arrow_down)),
              IconButton(tooltip: t.closeSearch, onPressed: onClose, icon: const Icon(Icons.close_rounded)),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a connection failure tells the user.
String connectProblemText(AppLocalizations t, ConnectProblem problem) => switch (problem) {
  ConnectProblem.unreachable => t.errConnUnreachable,
  ConnectProblem.timeout => t.errConnTimeout,
  ConnectProblem.authFailed => t.errConnAuthFailed,
  ConnectProblem.hostKeyRejected => t.errConnHostKeyRejected,
  ConnectProblem.keyInvalid => t.errConnKeyInvalid,
  ConnectProblem.keyPassphraseRequired => t.errConnKeyPassphraseRequired,
  ConnectProblem.keyPassphraseWrong => t.errConnKeyPassphraseWrong,
  ConnectProblem.disconnected => t.errConnDisconnected,
  ConnectProblem.localShellFailed => t.errLocalShell,
  ConnectProblem.serialFailed => t.errSerial,
};

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.session,
    required this.onReconnect,
    this.reconnectIn,
    this.attempt = 1,
    this.onCancel,
  });

  final TerminalSession session;
  final VoidCallback onReconnect;

  /// Seconds before the next automatic reconnection; null when none waits.
  final int? reconnectIn;
  final int attempt;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final connecting = session.state == SessionState.connecting;
    final message = connecting
        ? t.connectingTo(session.target.label)
        : switch (session.problem) {
            null => t.disconnected,
            final problem => connectProblemText(t, problem),
          };
    final via = session.problemVia;
    final shown = !connecting && session.problem != null && via != null ? t.errConnVia(via, message) : message;

    return Material(
      color: c.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        // In a narrow pane the buttons go under the text.
        child: LayoutBuilder(
          builder: (context, box) {
            final status = Row(
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
                  child: Text(
                    reconnectIn == null
                        ? shown
                        : '$shown ${t.reconnectingIn(reconnectIn!, attempt, reconnectDelays.length)}',
                    key: const ValueKey('sessionStatus'),
                    style: TextStyle(color: c.ink),
                  ),
                ),
              ],
            );
            final buttons = [
              if (reconnectIn != null && onCancel != null)
                TextButton(key: const ValueKey('cancelReconnect'), onPressed: onCancel, child: Text(t.cancel)),
              if (!connecting)
                TextButton(
                  key: const ValueKey('reconnectNow'),
                  onPressed: onReconnect,
                  child: Text(reconnectIn == null ? t.reconnect : t.reconnectNow),
                ),
            ];
            if (buttons.isEmpty) return status;
            if (box.maxWidth >= 420) {
              return Row(
                children: [
                  Expanded(child: status),
                  ...buttons,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                status,
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(children: buttons),
                ),
              ],
            );
          },
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
