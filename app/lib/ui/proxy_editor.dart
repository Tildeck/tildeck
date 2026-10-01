import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ssh/proxy.dart';
import '../theme.dart';
import '../vault/models.dart';
import '../vault/vault.dart';

/// Adds or edits a proxy; returns its id, or null when cancelled or deleted.
Future<String?> showProxyEditor(BuildContext context, Vault vault, {ProxyEntry? proxy}) => showDialog<String>(
  context: context,
  builder: (_) => _ProxyEditor(vault: vault, proxy: proxy),
);

/// A proxy picker for a host or a group, with buttons to add one or edit the
/// chosen one.
class ProxyField extends StatelessWidget {
  const ProxyField({super.key, required this.vault, required this.value, required this.onChanged, this.helperText});

  final Vault vault;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final proxies = vault.proxies;
    final chosen = vault.entry<ProxyEntry>(value);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            // Rebuilt when the list changes, so a new proxy can be chosen.
            key: ValueKey('proxyChoice-${proxies.length}-$value'),
            initialValue: chosen?.id,
            isExpanded: true,
            decoration: InputDecoration(labelText: t.proxyLabel, helperText: helperText, helperMaxLines: 3),
            items: [
              DropdownMenuItem(value: null, child: Text(t.noProxy)),
              for (final p in proxies) DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: chosen == null
              ? IconButton(
                  key: const ValueKey('addProxy'),
                  tooltip: t.addProxy,
                  icon: const Icon(Icons.add),
                  onPressed: () async {
                    final id = await showProxyEditor(context, vault);
                    if (id != null) onChanged(id);
                  },
                )
              : IconButton(
                  key: const ValueKey('editProxy'),
                  tooltip: t.editProxy,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final id = await showProxyEditor(context, vault, proxy: chosen);
                    if (id == null && vault.entry<ProxyEntry>(chosen.id) == null) onChanged(null);
                  },
                ),
        ),
      ],
    );
  }
}

class _ProxyEditor extends StatefulWidget {
  const _ProxyEditor({required this.vault, this.proxy});

  final Vault vault;
  final ProxyEntry? proxy;

  @override
  State<_ProxyEditor> createState() => _ProxyEditorState();
}

class _ProxyEditorState extends State<_ProxyEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.proxy?.name);
  late final _host = TextEditingController(text: widget.proxy?.host);
  late final _port = TextEditingController(text: '${widget.proxy?.port ?? 1080}');
  late final _username = TextEditingController(text: widget.proxy?.username);
  late final _password = TextEditingController(text: widget.proxy?.password);
  late ProxyKind _kind = widget.proxy?.kind ?? ProxyKind.socks5;

  @override
  void dispose() {
    for (final c in [_name, _host, _port, _username, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final id = widget.proxy?.id ?? widget.vault.newId();
    final username = _username.text.trim();
    await widget.vault.put(
      ProxyEntry(
        id: id,
        name: _name.text.trim(),
        kind: _kind,
        host: _host.text.trim(),
        port: int.parse(_port.text.trim()),
        username: username.isEmpty ? null : username,
        password: username.isEmpty || _password.text.isEmpty ? null : _password.text,
      ),
    );
    if (mounted) Navigator.pop(context, id);
  }

  Future<void> _delete() async {
    await widget.vault.delete(widget.proxy!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    String? required(String? v) => (v ?? '').trim().isEmpty ? t.fieldRequired : null;
    String? port(String? v) {
      final n = int.tryParse((v ?? '').trim());
      return n == null || n < 1 || n > 65535 ? t.portInvalid : null;
    }

    Widget ltr(
      TextEditingController controller,
      String label,
      Key key, {
      bool number = false,
      bool secret = false,
      String? Function(String?)? validator,
    }) => TextFormField(
      key: key,
      controller: controller,
      textDirection: TextDirection.ltr,
      obscureText: secret,
      keyboardType: number ? TextInputType.number : TextInputType.url,
      autocorrect: false,
      validator: validator,
      decoration: InputDecoration(labelText: label),
    );

    return AlertDialog(
      title: Text(widget.proxy == null ? t.addProxy : t.editProxy),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('proxyName'),
                  controller: _name,
                  validator: required,
                  decoration: InputDecoration(labelText: t.forwardNameLabel, hintText: t.proxyNameHint),
                ),
                const SizedBox(height: 12),
                SegmentedButton<ProxyKind>(
                  key: const ValueKey('proxyKind'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ProxyKind.socks5, label: Text('SOCKS5')),
                    ButtonSegment(value: ProxyKind.http, label: Text('HTTP')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() => _kind = s.first),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: ltr(_host, t.hostLabel, const ValueKey('proxyHost'), validator: required)),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 96,
                      child: ltr(_port, t.portLabel, const ValueKey('proxyPort'), number: true, validator: port),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ltr(_username, t.usernameLabel, const ValueKey('proxyUsername')),
                const SizedBox(height: 12),
                ltr(_password, t.passwordLabel, const ValueKey('proxyPassword'), secret: true),
                const SizedBox(height: 8),
                Text(t.proxyCredentialsHelp, style: TextStyle(color: c.muted, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.proxy != null)
          TextButton(
            key: const ValueKey('deleteProxy'),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            onPressed: _delete,
            child: Text(t.deleteAction),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(key: const ValueKey('saveProxy'), onPressed: _save, child: Text(t.save)),
      ],
    );
  }
}
