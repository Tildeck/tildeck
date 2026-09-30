import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../server_check.dart';
import '../theme.dart';

/// Check a sync server: that it is a Tildeck server this app can sync with.
/// Accounts and sync itself arrive in later product steps.
class SyncServerPage extends StatefulWidget {
  const SyncServerPage({super.key, required this.checker});

  final ServerChecker checker;

  @override
  State<SyncServerPage> createState() => _SyncServerPageState();
}

class _SyncServerPageState extends State<SyncServerPage> {
  final _address = TextEditingController();
  bool _checking = false;
  ServerCheckResult? _result;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    final result = await widget.checker.check(_address.text);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: c.desk,
        foregroundColor: c.deskInk,
        title: Text(t.syncServerTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              children: [
                Text(t.connectTitle, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.15)),
                const SizedBox(height: 10),
                Text(t.connectIntro, style: text.bodyLarge?.copyWith(color: c.muted, height: 1.5)),
                const SizedBox(height: 28),
                // An address is Latin content end to end: always LTR, even
                // in a Hebrew interface.
                TextField(
                  controller: _address,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onSubmitted: (_) => _check(),
                  decoration: InputDecoration(labelText: t.serverAddressLabel, hintText: t.serverAddressHint),
                ),
                const SizedBox(height: 14),
                FilledButton(onPressed: _checking ? null : _check, child: Text(_checking ? t.checking : t.checkServer)),
                const SizedBox(height: 20),
                if (_result != null) _ResultCard(result: _result!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final ServerCheckResult result;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final (ok, title, lines) = switch (result) {
      ServerReady(:final info) => (
        true,
        t.serverReady,
        [t.serverVersion(info.version), t.protocolVersion(info.protocolVersion)],
      ),
      ServerFailed(:final problem) => (false, _message(t, problem), const <String>[]),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ok ? c.line : c.danger),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: ok ? c.success : c.danger, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(line, style: text.bodyMedium?.copyWith(color: c.muted)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _message(AppLocalizations t, ServerProblem problem) => switch (problem) {
    ServerProblem.invalidAddress => t.errorInvalidAddress,
    ServerProblem.unreachable => t.errorUnreachable,
    ServerProblem.notTildeck => t.errorNotTildeck,
    ServerProblem.unsupportedProtocol => t.errorUnsupportedProtocol,
    ServerProblem.databaseUnavailable => t.errorDatabaseUnavailable,
  };
}
