import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../vault/models.dart';
import '../vault/vault.dart';
import 'keys_page.dart' show showKeyEditor, showKeyGenerator;

/// Who to sign in as, saved once for many hosts: a username with a key or a
/// password. They live in the vault, so they sync like hosts.
class IdentitiesPage extends StatelessWidget {
  const IdentitiesPage({super.key, required this.vault});

  final Vault vault;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.identitiesTitle),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: FilledButton.icon(
              key: const ValueKey('addIdentity'),
              onPressed: () => showIdentityEditor(context, vault),
              icon: const Icon(Icons.add),
              label: Text(t.addIdentity),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: vault,
        builder: (context, _) {
          final identities = vault.identities;
          if (identities.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Text(
                    t.noIdentitiesYet,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted, height: 1.5),
                  ),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: identities.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final identity = identities[i];
              final users = vault.hosts.where((h) => h.identityId == identity.id).length;
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  key: ValueKey('identity-${identity.name}'),
                  leading: Icon(Icons.badge_outlined, color: c.brand),
                  title: Text(identity.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    '${identityCredentials(t, vault, identity)} · ${t.identityHostCount(users)}',
                    style: TextStyle(color: c.muted),
                  ),
                  onTap: () => showIdentityEditor(context, vault, identity: identity),
                  trailing: IconButton(
                    key: ValueKey('deleteIdentity-${identity.name}'),
                    tooltip: t.deleteAction,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      if (vault.hosts.any((h) => h.identityId == identity.id) ||
                          vault.groups.any((g) => g.identityId == identity.id)) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.identityInUse)));
                        return;
                      }
                      vault.delete(identity.id);
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// How an identity signs in, in a few words: "deploy, key Build key".
String identityCredentials(AppLocalizations t, Vault vault, IdentityEntry identity) {
  final key = vault.entry<KeyEntry>(identity.keyId);
  final how = key != null
      ? t.identityWithKey(key.name)
      : identity.password != null
      ? t.identityWithPassword
      : t.identityAsksPassword;
  return '${identity.username}, $how';
}

/// Adds or edits an identity; returns its id.
Future<String?> showIdentityEditor(BuildContext context, Vault vault, {IdentityEntry? identity}) => showDialog<String>(
  context: context,
  builder: (_) => _IdentityEditor(vault: vault, identity: identity),
);

class _IdentityEditor extends StatefulWidget {
  const _IdentityEditor({required this.vault, this.identity});

  final Vault vault;
  final IdentityEntry? identity;

  @override
  State<_IdentityEditor> createState() => _IdentityEditorState();
}

class _IdentityEditorState extends State<_IdentityEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.identity?.name);
  late final _username = TextEditingController(text: widget.identity?.username);
  late final _password = TextEditingController(text: widget.identity?.password);
  late HostAuth _auth = widget.identity?.auth ?? HostAuth.password;
  late bool _savePassword = widget.identity?.password != null;
  late String? _keyId = widget.identity?.keyId;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final id = widget.identity?.id ?? widget.vault.newId();
    await widget.vault.put(
      IdentityEntry(
        id: id,
        name: _name.text.trim(),
        username: _username.text.trim(),
        password: _auth == HostAuth.password && _savePassword ? _password.text : null,
        keyId: _auth == HostAuth.key ? _keyId : null,
      ),
    );
    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    String? required(String? v) => (v == null || v.trim().isEmpty) ? t.fieldRequired : null;
    final keys = widget.vault.keys;
    return AlertDialog(
      title: Text(widget.identity == null ? t.addIdentity : t.editIdentity),
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
                  key: const ValueKey('identityName'),
                  controller: _name,
                  autofocus: widget.identity == null,
                  validator: required,
                  decoration: InputDecoration(labelText: t.identityNameLabel, hintText: t.identityNameHint),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('identityUsername'),
                  controller: _username,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  validator: required,
                  decoration: InputDecoration(labelText: t.usernameLabel),
                ),
                const SizedBox(height: 18),
                SegmentedButton<HostAuth>(
                  segments: [
                    ButtonSegment(
                      value: HostAuth.password,
                      label: Text(t.authPassword),
                      icon: const Icon(Icons.password),
                    ),
                    ButtonSegment(value: HostAuth.key, label: Text(t.authPrivateKey), icon: const Icon(Icons.key)),
                  ],
                  selected: {_auth},
                  onSelectionChanged: (s) => setState(() => _auth = s.first),
                ),
                const SizedBox(height: 14),
                if (_auth == HostAuth.password) ...[
                  SwitchListTile(
                    key: const ValueKey('identitySavePassword'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.savePassword),
                    subtitle: Text(t.askPasswordEachTime, style: TextStyle(color: c.muted)),
                    value: _savePassword,
                    onChanged: (v) => setState(() => _savePassword = v),
                  ),
                  if (_savePassword)
                    TextFormField(
                      key: const ValueKey('identityPassword'),
                      controller: _password,
                      obscureText: true,
                      textDirection: TextDirection.ltr,
                      validator: required,
                      decoration: InputDecoration(labelText: t.passwordLabel),
                    ),
                ] else ...[
                  DropdownButtonFormField<String>(
                    key: const ValueKey('identityKey'),
                    initialValue: keys.any((k) => k.id == _keyId) ? _keyId : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t.keyLabel, hintText: t.chooseKey),
                    validator: (v) => v == null ? t.fieldRequired : null,
                    items: [for (final k in keys) DropdownMenuItem(value: k.id, child: Text(k.name))],
                    onChanged: (v) => setState(() => _keyId = v),
                  ),
                  Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: Text(t.generateKey),
                        onPressed: () async {
                          final id = await showKeyGenerator(context, widget.vault);
                          if (id != null) setState(() => _keyId = id);
                        },
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.file_download_outlined),
                        label: Text(t.importKey),
                        onPressed: () async {
                          final id = await showKeyEditor(context, widget.vault);
                          if (id != null) setState(() => _keyId = id);
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(key: const ValueKey('saveIdentity'), onPressed: _save, child: Text(t.save)),
      ],
    );
  }
}
