import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ssh/port_forwarding.dart';
import '../theme.dart';
import '../vault/models.dart';
import '../vault/vault.dart';

String forwardProblemText(AppLocalizations t, ForwardProblem p) => switch (p) {
  ForwardProblem.connectFailed => t.forwardErrorConnect,
  ForwardProblem.portInUse => t.forwardErrorPort,
  ForwardProblem.refusedByServer => t.forwardErrorRefused,
  ForwardProblem.failed => t.forwardErrorFailed,
};

/// Port forwarding rules: start and stop them, add, edit, delete. A running
/// rule keeps its own connection to its host.
class PortForwardsPage extends StatelessWidget {
  const PortForwardsPage({super.key, required this.vault, required this.manager, required this.connect});

  final Vault vault;
  final ForwardManager manager;

  /// Opens an authenticated connection to a saved host (asking for its
  /// password or host key when needed).
  final Future<SSHClient> Function(BuildContext context, HostEntry host) connect;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.forwardsTitle),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: FilledButton.icon(
              key: const ValueKey('addForward'),
              onPressed: vault.hosts.isEmpty ? null : () => showForwardEditor(context, vault),
              icon: const Icon(Icons.add),
              label: Text(t.addForward),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([vault, manager]),
        builder: (context, _) {
          final rules = vault.forwards;
          if (rules.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  vault.hosts.isEmpty ? t.forwardsNeedHost : t.noForwardsYet,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted, height: 1.5),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rules.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _RuleCard(rule: rules[i], vault: vault, manager: manager, connect: connect),
          );
        },
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.rule, required this.vault, required this.manager, required this.connect});

  final PortForwardEntry rule;
  final Vault vault;
  final ForwardManager manager;
  final Future<SSHClient> Function(BuildContext context, HostEntry host) connect;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final host = vault.entry<HostEntry>(rule.hostId);
    final active = manager.active(rule.id);
    final starting = manager.isStarting(rule.id);
    final problem = manager.problemOf(rule.id);
    final status = active != null
        ? t.forwardListening(
            '${rule.kind == ForwardKind.remote ? t.forwardOnServer : rule.bindHost}:${active.boundPort}',
            active.connections,
          )
        : starting
        ? t.working
        : problem != null
        ? forwardProblemText(t, problem)
        : t.forwardStopped;
    final kindLabel = switch (rule.kind) {
      ForwardKind.local => t.forwardLocal,
      ForwardKind.remote => t.forwardRemote,
      ForwardKind.dynamic => t.forwardDynamic,
    };
    return Card(
      key: ValueKey('forward-${rule.name}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(Icons.swap_horiz_rounded, color: active != null ? c.success : c.muted),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          rule.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                        decoration: BoxDecoration(
                          color: c.brand.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(kindLabel, style: TextStyle(fontSize: 12, color: c.brand)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rule.summary,
                    textDirection: TextDirection.ltr,
                    // Addresses read LTR, but sit on the reading side of the card.
                    textAlign: Directionality.of(context) == TextDirection.rtl ? TextAlign.right : TextAlign.left,
                    style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13, color: c.muted),
                  ),
                  Text(
                    '${host?.name ?? t.forwardHostMissing}  ·  $status',
                    key: ValueKey('forwardStatus-${rule.name}'),
                    style: TextStyle(fontSize: 12, color: problem != null && active == null ? c.danger : c.muted),
                  ),
                ],
              ),
            ),
            Switch(
              key: ValueKey('forwardSwitch-${rule.name}'),
              value: active != null || starting,
              onChanged: host == null || starting
                  ? null
                  : (on) => on ? manager.start(rule, () => connect(context, host)) : manager.stop(rule.id),
            ),
            PopupMenuButton<String>(
              onSelected: (action) async {
                if (action == 'edit') {
                  await showForwardEditor(context, vault, rule: rule);
                } else {
                  await manager.stop(rule.id);
                  await vault.delete(rule.id);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(t.editAction)),
                PopupMenuItem(value: 'delete', child: Text(t.deleteAction)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Adds or edits a rule.
Future<void> showForwardEditor(BuildContext context, Vault vault, {PortForwardEntry? rule}) => showDialog<void>(
  context: context,
  builder: (_) => _ForwardEditor(vault: vault, rule: rule),
);

class _ForwardEditor extends StatefulWidget {
  const _ForwardEditor({required this.vault, this.rule});

  final Vault vault;
  final PortForwardEntry? rule;

  @override
  State<_ForwardEditor> createState() => _ForwardEditorState();
}

class _ForwardEditorState extends State<_ForwardEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.rule?.name);
  late final _bindHost = TextEditingController(text: widget.rule?.bindHost ?? '127.0.0.1');
  late final _bindPort = TextEditingController(text: widget.rule == null ? '' : '${widget.rule!.bindPort}');
  late final _destHost = TextEditingController(text: widget.rule?.destHost ?? 'localhost');
  late final _destPort = TextEditingController(
    text: widget.rule == null || widget.rule!.destPort == 0 ? '' : '${widget.rule!.destPort}',
  );
  late ForwardKind _kind = widget.rule?.kind ?? ForwardKind.local;
  late String? _hostId = widget.rule?.hostId ?? (widget.vault.hosts.isEmpty ? null : widget.vault.hosts.first.id);

  @override
  void dispose() {
    for (final c in [_name, _bindHost, _bindPort, _destHost, _destPort]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await widget.vault.put(
      PortForwardEntry(
        id: widget.rule?.id ?? widget.vault.newId(),
        name: _name.text.trim(),
        hostId: _hostId!,
        kind: _kind,
        bindHost: _bindHost.text.trim(),
        bindPort: int.parse(_bindPort.text.trim()),
        destHost: _kind == ForwardKind.dynamic ? '' : _destHost.text.trim(),
        destPort: _kind == ForwardKind.dynamic ? 0 : int.parse(_destPort.text.trim()),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
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
      String? Function(String?)? validator,
    }) => TextFormField(
      key: key,
      controller: controller,
      textDirection: TextDirection.ltr,
      keyboardType: number ? TextInputType.number : TextInputType.url,
      autocorrect: false,
      validator: validator,
      decoration: InputDecoration(labelText: label),
    );

    return AlertDialog(
      title: Text(widget.rule == null ? t.addForward : t.editForward),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('forwardName'),
                  controller: _name,
                  autofocus: true,
                  validator: required,
                  decoration: InputDecoration(labelText: t.forwardNameLabel, hintText: t.forwardNameHint),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('forwardHost'),
                  initialValue: _hostId,
                  decoration: InputDecoration(labelText: t.forwardHostLabel),
                  validator: (v) => v == null ? t.fieldRequired : null,
                  items: [for (final h in widget.vault.hosts) DropdownMenuItem(value: h.id, child: Text(h.name))],
                  onChanged: (v) => setState(() => _hostId = v),
                ),
                const SizedBox(height: 12),
                SegmentedButton<ForwardKind>(
                  key: const ValueKey('forwardKind'),
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: ForwardKind.local, label: Text(t.forwardLocal)),
                    ButtonSegment(value: ForwardKind.remote, label: Text(t.forwardRemote)),
                    ButtonSegment(value: ForwardKind.dynamic, label: Text(t.forwardDynamic)),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() => _kind = s.first),
                ),
                const SizedBox(height: 6),
                Text(switch (_kind) {
                  ForwardKind.local => t.forwardLocalHelp,
                  ForwardKind.remote => t.forwardRemoteHelp,
                  ForwardKind.dynamic => t.forwardDynamicHelp,
                }, style: TextStyle(color: context.colors.muted, fontSize: 13, height: 1.4)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ltr(
                        _bindHost,
                        _kind == ForwardKind.remote ? t.forwardServerAddress : t.forwardListenAddress,
                        const ValueKey('forwardBindHost'),
                        validator: required,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ltr(
                        _bindPort,
                        t.portLabel,
                        const ValueKey('forwardBindPort'),
                        number: true,
                        validator: port,
                      ),
                    ),
                  ],
                ),
                if (_kind != ForwardKind.dynamic) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: ltr(
                          _destHost,
                          t.forwardDestination,
                          const ValueKey('forwardDestHost'),
                          validator: required,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ltr(
                          _destPort,
                          t.portLabel,
                          const ValueKey('forwardDestPort'),
                          number: true,
                          validator: port,
                        ),
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
        FilledButton(key: const ValueKey('saveForward'), onPressed: _save, child: Text(t.save)),
      ],
    );
  }
}
