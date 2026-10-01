import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../vault/models.dart';
import '../vault/vault.dart';

/// The servers whose keys this vault trusts, with their fingerprints.
/// Removing one makes the next connection ask again, as for a new server.
class KnownHostsPage extends StatefulWidget {
  const KnownHostsPage({super.key, required this.vault});

  final Vault vault;

  @override
  State<KnownHostsPage> createState() => _KnownHostsPageState();
}

class _KnownHostsPageState extends State<KnownHostsPage> {
  String _query = '';

  Future<void> _remove(KnownHostEntry entry) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await widget.vault.delete(entry.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(t.knownHostRemoved),
        action: SnackBarAction(label: t.undo, onPressed: () => widget.vault.put(entry)),
      ),
    );
  }

  static String _address(KnownHostEntry e) => e.port == 22 ? e.host : '${e.host}:${e.port}';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final ltrStart = Directionality.of(context) == TextDirection.rtl ? TextAlign.right : TextAlign.left;
    return Scaffold(
      appBar: AppBar(title: Text(t.knownHostsTitle)),
      body: ListenableBuilder(
        listenable: widget.vault,
        builder: (context, _) {
          final all = widget.vault.knownHosts..sort((a, b) => _address(a).compareTo(_address(b)));
          final query = _query.trim().toLowerCase();
          final shown = query.isEmpty ? all : all.where((e) => _address(e).toLowerCase().contains(query)).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(t.knownHostsIntro, style: TextStyle(color: c.muted, height: 1.45)),
              const SizedBox(height: 14),
              if (all.length > 5)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    key: const ValueKey('knownHostsSearch'),
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t.searchServers),
                  ),
                ),
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    t.noKnownHosts,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted),
                  ),
                ),
              for (final e in shown)
                Card.outlined(
                  key: ValueKey('knownHost-${_address(e)}'),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(Icons.verified_user_outlined, color: c.brand),
                    title: Text(
                      _address(e),
                      textDirection: TextDirection.ltr,
                      textAlign: ltrStart,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    // The whole fingerprint: it is what is compared.
                    subtitle: Text(
                      '${e.keyType}\n${e.fingerprint}',
                      textDirection: TextDirection.ltr,
                      textAlign: ltrStart,
                      style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11.5, height: 1.4),
                    ),
                    trailing: IconButton(
                      key: ValueKey('forget-${_address(e)}'),
                      tooltip: t.forgetKnownHost,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _remove(e),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
