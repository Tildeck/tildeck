import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ssh/terminal_session.dart';
import '../theme.dart';
import '../vault/vault.dart';
import 'snippets_page.dart';

/// The commands a session can offer again, newest first: those run in it,
/// then the server's own history, each once.
List<String> recentCommands(TerminalSession session, {int limit = 300}) {
  final seen = <String>{};
  return [
    for (final c in [...session.commands.reversed, ...session.history.reversed])
      if (seen.add(c)) c,
  ].take(limit).toList();
}

/// Lists [session]'s recent commands: a tap puts one on the line (the user
/// still presses Enter), and each can be saved as a snippet.
Future<void> showCommandHistory(BuildContext context, Vault vault, TerminalSession session) async {
  final command = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CommandHistory(vault: vault, session: session),
  );
  if (command != null) session.complete(command);
}

class _CommandHistory extends StatelessWidget {
  const _CommandHistory({required this.vault, required this.session});

  final Vault vault;
  final TerminalSession session;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final commands = recentCommands(session);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
              child: Text(t.commandsTitle, style: Theme.of(context).textTheme.titleLarge),
            ),
            if (commands.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: Text(
                  t.noCommandsYet,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (i, command) in commands.indexed)
                      ListTile(
                        key: ValueKey('command-$i'),
                        leading: Icon(Icons.history_rounded, color: c.muted),
                        title: Text(
                          command,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          textAlign: rtl ? TextAlign.right : TextAlign.left,
                          style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13),
                        ),
                        onTap: () => Navigator.pop(context, command),
                        trailing: IconButton(
                          key: ValueKey('saveCommand-$i'),
                          tooltip: t.saveAsSnippet,
                          icon: const Icon(Icons.bookmark_add_outlined),
                          onPressed: () => showSnippetEditor(context, vault, command: command),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
