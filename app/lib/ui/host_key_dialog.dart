import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ssh/known_hosts.dart';
import '../ssh/ssh_connector.dart';
import '../theme.dart';

/// Asks whether to trust a server's key. For a changed key the safe answer,
/// cancel, is the prominent one; replacing the key takes a deliberate tap.
Future<bool> showHostKeyDialog(
  BuildContext context, {
  required ConnectionTarget target,
  required KnownHost presented,
  required HostKeyStatus status,
  KnownHost? previous,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => HostKeyDialog(target: target, presented: presented, status: status, previous: previous),
  );
  return result ?? false;
}

class HostKeyDialog extends StatelessWidget {
  const HostKeyDialog({super.key, required this.target, required this.presented, required this.status, this.previous});

  final ConnectionTarget target;
  final KnownHost presented;
  final HostKeyStatus status;
  final KnownHost? previous;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final changed = status == HostKeyStatus.changed;
    final host = target.port == 22 ? target.host : '${target.host}:${target.port}';

    Widget fingerprint(String label, KnownHost key, {bool strike = false}) => Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelMedium?.copyWith(color: c.muted)),
          const SizedBox(height: 4),
          // Fingerprints are Latin content: always LTR, selectable to compare.
          Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(
              '${key.type}\n${key.fingerprint}',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 12.5,
                height: 1.4,
                color: strike ? c.muted : c.ink,
                decoration: strike ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );

    return AlertDialog(
      icon: Icon(
        changed ? Icons.gpp_maybe : Icons.verified_user_outlined,
        color: changed ? c.danger : c.brand,
        size: 32,
      ),
      title: Text(changed ? t.hostKeyChangedTitle : t.hostKeyNewTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(changed ? t.hostKeyChangedBody(host) : t.hostKeyNewBody(host)),
            if (changed && previous != null) fingerprint(t.hostKeyPrevious, previous!, strike: true),
            fingerprint(t.hostKeyFingerprint, presented),
          ],
        ),
      ),
      actions: changed
          ? [
              TextButton(
                key: const ValueKey('replaceHostKey'),
                style: TextButton.styleFrom(foregroundColor: c.danger),
                onPressed: () => Navigator.pop(context, true),
                child: Text(t.replaceAndConnect),
              ),
              FilledButton(
                key: const ValueKey('cancelHostKey'),
                onPressed: () => Navigator.pop(context, false),
                child: Text(t.cancel),
              ),
            ]
          : [
              TextButton(
                key: const ValueKey('cancelHostKey'),
                onPressed: () => Navigator.pop(context, false),
                child: Text(t.cancel),
              ),
              FilledButton(
                key: const ValueKey('trustHostKey'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(t.trustAndConnect),
              ),
            ],
    );
  }
}
