import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../vault/models.dart';
import '../vault/vault.dart';

/// Past connections, newest first, from every device of the account.
/// Tapping one with a saved host connects to it again.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.vault, required this.onReconnect});

  final Vault vault;
  final void Function(HostEntry host) onReconnect;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Scaffold(
      appBar: AppBar(title: Text(t.historyTitle)),
      body: ListenableBuilder(
        listenable: vault,
        builder: (context, _) {
          final history = vault.history;
          if (history.isEmpty) {
            return Center(
              child: Text(t.historyEmpty, style: TextStyle(color: c.muted)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: history.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: c.line),
            itemBuilder: (context, i) {
              final entry = history[i];
              final host = vault.entry<HostEntry>(entry.hostId);
              final when = DateFormat.yMMMd(locale).add_Hm().format(entry.startedAt.toLocal());
              final details = [
                when,
                if (entry.endedAt != null) durationText(t, entry.endedAt!.difference(entry.startedAt)),
                if (entry.device != null) entry.device!,
              ].join('  ·  ');
              return ListTile(
                key: ValueKey('history-$i'),
                leading: Icon(
                  entry.failed ? Icons.error_outline_rounded : Icons.history_rounded,
                  color: entry.failed ? c.danger : c.brand,
                ),
                title: Text(host?.name ?? entry.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      entry.label,
                      textDirection: TextDirection.ltr,
                      textAlign: Directionality.of(context) == TextDirection.rtl ? TextAlign.right : TextAlign.left,
                    ),
                    Text(details, style: TextStyle(color: c.muted, fontSize: 12)),
                  ],
                ),
                trailing: host == null ? null : Icon(Icons.replay_rounded, color: c.muted),
                onTap: host == null
                    ? null
                    : () {
                        Navigator.pop(context);
                        onReconnect(host);
                      },
              );
            },
          );
        },
      ),
    );
  }
}

/// A connection's length, in the largest sensible units.
String durationText(AppLocalizations t, Duration d) {
  if (d.inHours > 0) return t.durationHours(d.inHours, d.inMinutes % 60);
  if (d.inMinutes > 0) return t.durationMinutes(d.inMinutes);
  return t.durationSeconds(d.inSeconds);
}
