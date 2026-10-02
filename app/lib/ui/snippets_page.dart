import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../vault/models.dart';
import '../vault/vault.dart';

const _mono = TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13, height: 1.4);

/// Saved commands. They live in the vault, so they sync like hosts.
class SnippetsPage extends StatelessWidget {
  const SnippetsPage({super.key, required this.vault});

  final Vault vault;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.snippetsTitle),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: FilledButton.icon(
              key: const ValueKey('addSnippet'),
              onPressed: () => showSnippetEditor(context, vault),
              icon: const Icon(Icons.add),
              label: Text(t.addSnippet),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: vault,
        builder: (context, _) {
          final snippets = vault.snippets;
          if (snippets.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  t.noSnippetsYet,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted, height: 1.5),
                ),
              ),
            );
          }
          // By folder, alphabetically; those in none last.
          final folders = snippets.map((s) => s.folder).toSet().toList()
            ..sort((a, b) => a.isEmpty ? 1 : (b.isEmpty ? -1 : a.toLowerCase().compareTo(b.toLowerCase())));
          final rows = <Object>[
            for (final folder in folders) ...[
              if (folders.length > 1 || folder.isNotEmpty) folder,
              ...snippets.where((s) => s.folder == folder),
            ],
          ];
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final row = rows[i];
              if (row is String) {
                return Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(4, 10, 4, 0),
                  child: Row(
                    children: [
                      Icon(Icons.folder_outlined, size: 18, color: c.muted),
                      const SizedBox(width: 8),
                      Text(
                        row.isEmpty ? t.ungrouped : row,
                        key: ValueKey('snippetFolder-$row'),
                        style: TextStyle(color: c.muted, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                );
              }
              final snippet = row as SnippetEntry;
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  key: ValueKey('snippet-${snippet.name}'),
                  leading: Icon(Icons.code_rounded, color: c.brand),
                  title: Text(snippet.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    snippet.command,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    // A command reads left to right, but sits at the start of the row.
                    textAlign: Directionality.of(context) == TextDirection.rtl ? TextAlign.right : TextAlign.left,
                    style: _mono.copyWith(color: c.muted),
                  ),
                  onTap: () => showSnippetEditor(context, vault, snippet: snippet),
                  trailing: IconButton(
                    tooltip: t.deleteAction,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => vault.delete(snippet.id),
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

/// Adds or edits a snippet; returns its id.
Future<String?> showSnippetEditor(BuildContext context, Vault vault, {SnippetEntry? snippet}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _SnippetEditor(vault: vault, snippet: snippet),
  );
}

class _SnippetEditor extends StatefulWidget {
  const _SnippetEditor({required this.vault, this.snippet});

  final Vault vault;
  final SnippetEntry? snippet;

  @override
  State<_SnippetEditor> createState() => _SnippetEditorState();
}

class _SnippetEditorState extends State<_SnippetEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.snippet?.name);
  late final _command = TextEditingController(text: widget.snippet?.command);
  late final _folder = TextEditingController(text: widget.snippet?.folder);

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    _folder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final entry = SnippetEntry(
      id: widget.snippet?.id ?? widget.vault.newId(),
      name: _name.text.trim(),
      command: _command.text,
      folder: _folder.text.trim(),
    );
    await widget.vault.put(entry);
    if (mounted) Navigator.pop(context, entry.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    String? required(String? v) => (v ?? '').trim().isEmpty ? t.fieldRequired : null;
    return AlertDialog(
      title: Text(widget.snippet == null ? t.addSnippet : t.editSnippet),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('snippetName'),
                controller: _name,
                autofocus: true,
                validator: required,
                decoration: InputDecoration(labelText: t.snippetNameLabel, hintText: t.snippetNameHint),
              ),
              const SizedBox(height: 14),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _folder.text),
                optionsBuilder: (value) {
                  final typed = value.text.trim().toLowerCase();
                  return {
                    for (final s in widget.vault.snippets)
                      if (s.folder.isNotEmpty && s.folder.toLowerCase().contains(typed)) s.folder,
                  };
                },
                onSelected: (v) => _folder.text = v,
                fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
                  key: const ValueKey('snippetFolder'),
                  controller: controller,
                  focusNode: focus,
                  onChanged: (v) => _folder.text = v,
                  decoration: InputDecoration(labelText: t.folderLabel, hintText: t.groupHint),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const ValueKey('snippetCommand'),
                controller: _command,
                minLines: 3,
                maxLines: 10,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                style: _mono,
                validator: required,
                decoration: InputDecoration(
                  labelText: t.snippetCommandLabel,
                  hintText: 'sudo systemctl restart nginx',
                  helperText: t.snippetCommandHelp,
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(key: const ValueKey('saveSnippet'), onPressed: _save, child: Text(t.save)),
      ],
    );
  }
}

/// What to do with a snippet picked from an open session.
sealed class SnippetChoice {
  const SnippetChoice(this.snippet);
  final SnippetEntry snippet;
}

class RunHere extends SnippetChoice {
  const RunHere(super.snippet);
}

class RunOnHosts extends SnippetChoice {
  const RunOnHosts(super.snippet, this.hosts);
  final List<HostEntry> hosts;
}

/// Picks a snippet to run in the current session, or on several saved
/// hosts at once, each in a new session.
Future<SnippetChoice?> showSnippetPicker(BuildContext context, Vault vault) {
  return showModalBottomSheet<SnippetChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SnippetPicker(vault: vault),
  );
}

class _SnippetPicker extends StatelessWidget {
  const _SnippetPicker({required this.vault});

  final Vault vault;

  Future<void> _onHosts(BuildContext context, SnippetEntry snippet) async {
    final hosts = await showDialog<List<HostEntry>>(
      context: context,
      builder: (_) => _HostChooser(hosts: vault.hosts, snippet: snippet),
    );
    if (hosts != null && hosts.isNotEmpty && context.mounted) Navigator.pop(context, RunOnHosts(snippet, hosts));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return ListenableBuilder(
      listenable: vault,
      builder: (context, _) {
        final snippets = vault.snippets;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(t.snippetsTitle, style: Theme.of(context).textTheme.titleLarge)),
                      TextButton.icon(
                        key: const ValueKey('pickerAddSnippet'),
                        onPressed: () => showSnippetEditor(context, vault),
                        icon: const Icon(Icons.add),
                        label: Text(t.addSnippet),
                      ),
                    ],
                  ),
                ),
                if (snippets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    child: Text(
                      t.noSnippetsYet,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.muted),
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final snippet in snippets)
                          ListTile(
                            key: ValueKey('run-${snippet.name}'),
                            leading: Icon(Icons.play_arrow_rounded, color: c.brand),
                            title: Text(snippet.folder.isEmpty ? snippet.name : '${snippet.folder} / ${snippet.name}'),
                            subtitle: Text(
                              snippet.command,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.ltr,
                              textAlign: Directionality.of(context) == TextDirection.rtl
                                  ? TextAlign.right
                                  : TextAlign.left,
                              style: _mono.copyWith(color: c.muted),
                            ),
                            onTap: () => Navigator.pop(context, RunHere(snippet)),
                            trailing: IconButton(
                              key: ValueKey('runOnHosts-${snippet.name}'),
                              tooltip: t.runOnHosts,
                              icon: const Icon(Icons.dynamic_feed_rounded),
                              onPressed: () => _onHosts(context, snippet),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HostChooser extends StatefulWidget {
  const _HostChooser({required this.hosts, required this.snippet});

  final List<HostEntry> hosts;
  final SnippetEntry snippet;

  @override
  State<_HostChooser> createState() => _HostChooserState();
}

class _HostChooserState extends State<_HostChooser> {
  final _chosen = <String>{};

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.runOnHostsTitle(widget.snippet.name)),
      content: SizedBox(
        width: 480,
        child: widget.hosts.isEmpty
            ? Text(t.noHostsYet)
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final host in widget.hosts)
                    CheckboxListTile(
                      key: ValueKey('chooseHost-${host.name}'),
                      value: _chosen.contains(host.id),
                      onChanged: (v) => setState(() => v == true ? _chosen.add(host.id) : _chosen.remove(host.id)),
                      title: Text(host.name),
                      subtitle: Text(host.label, textDirection: TextDirection.ltr),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          key: const ValueKey('runOnChosen'),
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.pop(context, [
                  for (final h in widget.hosts)
                    if (_chosen.contains(h.id)) h,
                ]),
          child: Text(t.runOnHostsButton(_chosen.length)),
        ),
      ],
    );
  }
}
