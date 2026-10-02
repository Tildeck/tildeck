import 'package:dartssh2/dartssh2.dart' show SSHUserInfoPrompt;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ssh/ssh_connector.dart';
import '../theme.dart';

/// A server's keyboard-interactive questions, as it wrote them: a one-time
/// code, or a password after the saved one was refused. Null when cancelled.
Future<List<String>?> showLoginPromptDialog(
  BuildContext context, {
  required ConnectionTarget target,
  required String name,
  required String instruction,
  required List<SSHUserInfoPrompt> prompts,
}) => showDialog<List<String>>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _LoginPromptDialog(target: target, name: name, instruction: instruction, prompts: prompts),
);

class _LoginPromptDialog extends StatefulWidget {
  const _LoginPromptDialog({
    required this.target,
    required this.name,
    required this.instruction,
    required this.prompts,
  });

  final ConnectionTarget target;
  final String name;
  final String instruction;
  final List<SSHUserInfoPrompt> prompts;

  @override
  State<_LoginPromptDialog> createState() => _LoginPromptDialogState();
}

class _LoginPromptDialogState extends State<_LoginPromptDialog> {
  late final _answers = [for (final _ in widget.prompts) TextEditingController()];

  @override
  void dispose() {
    for (final c in _answers) {
      c.dispose();
    }
    super.dispose();
  }

  void _done() => Navigator.pop(context, [for (final c in _answers) c.text]);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final address = widget.target.port == 22 ? widget.target.host : '${widget.target.host}:${widget.target.port}';
    // The server's own words: shown as it sent them, left to right.
    final said = [widget.name, widget.instruction].where((s) => s.trim().isNotEmpty).join('\n');
    return AlertDialog(
      title: Text(t.loginPromptTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.loginPromptIntro('${widget.target.username}@$address'), style: TextStyle(color: c.muted)),
              if (said.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(said, key: const ValueKey('loginPromptInstruction'), textDirection: TextDirection.ltr),
              ],
              for (final (i, prompt) in widget.prompts.indexed) ...[
                const SizedBox(height: 12),
                TextField(
                  key: ValueKey('loginPrompt-$i'),
                  controller: _answers[i],
                  autofocus: i == 0,
                  obscureText: !prompt.echo,
                  autocorrect: false,
                  textDirection: TextDirection.ltr,
                  textInputAction: i == widget.prompts.length - 1 ? TextInputAction.done : TextInputAction.next,
                  onSubmitted: (_) => i == widget.prompts.length - 1 ? _done() : null,
                  decoration: InputDecoration(labelText: prompt.promptText.trim().replaceAll(RegExp(r':$'), '')),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(key: const ValueKey('loginPromptContinue'), onPressed: _done, child: Text(t.continueButton)),
      ],
    );
  }
}
