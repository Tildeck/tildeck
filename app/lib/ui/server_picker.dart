import 'package:dartssh2/dartssh2.dart' show SSHClient;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ssh/file_browser.dart';
import '../theme.dart';
import '../vault/models.dart';
import '../vault/vault.dart';

/// Another server's files, to copy to: its browser and who and where.
typedef OtherServer = ({FileBrowser browser, String label});

/// Opens the files of a saved host the user picks, on a connection of
/// their own; null when cancelled. [except] is the server already shown.
Future<OtherServer?> pickOtherServer(
  BuildContext context,
  Vault vault,
  Future<SSHClient> Function(BuildContext context, HostEntry host) connect, {
  String? except,
}) async {
  final host = await showDialog<HostEntry>(
    context: context,
    builder: (_) => _ServerPicker(vault: vault, except: except),
  );
  if (host == null || !context.mounted) return null;
  SSHClient? client;
  final browser = FileBrowser(() async {
    final c = client = await connect(context, host);
    return c.sftp();
  }, onClose: () => client?.close());
  return (browser: browser, label: host.label);
}

class _ServerPicker extends StatelessWidget {
  const _ServerPicker({required this.vault, this.except});

  final Vault vault;
  final String? except;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final hosts = [
      for (final h in vault.hosts)
        if (!h.isTelnet && h.label != except) h,
    ];
    return AlertDialog(
      title: Text(t.copyToServerTitle),
      content: SizedBox(
        width: 420,
        height: 360,
        child: hosts.isEmpty
            ? Text(t.copyToServerNone, style: TextStyle(color: c.muted))
            : ListView(
                children: [
                  for (final h in hosts)
                    ListTile(
                      key: ValueKey('copyTarget-${h.name}'),
                      leading: Icon(Icons.dns_outlined, color: c.brand),
                      title: Text(h.name),
                      subtitle: Text(h.label, textDirection: TextDirection.ltr),
                      onTap: () => Navigator.pop(context, h),
                    ),
                ],
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel))],
    );
  }
}
