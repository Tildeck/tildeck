import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ssh/file_browser.dart';
import '../theme.dart';
import 'files_page.dart' show fileProblemText;

/// A remote text file, edited here and saved back over SFTP. Saving checks
/// that nobody changed the file on the server meanwhile.
class FileEditorPage extends StatefulWidget {
  const FileEditorPage({super.key, required this.browser, required this.file});

  final FileBrowser browser;
  final EditedFile file;

  @override
  State<FileEditorPage> createState() => _FileEditorPageState();
}

class _FileEditorPageState extends State<FileEditorPage> {
  late final _text = TextEditingController(text: widget.file.text);
  late String _saved = widget.file.text;
  var _saving = false;
  String? _problem;

  bool get _dirty => _text.text != _saved;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save({bool overwrite = false}) async {
    final t = AppLocalizations.of(context);
    setState(() {
      _saving = true;
      _problem = null;
    });
    final text = _text.text;
    final ok = await widget.browser.saveText(widget.file, text, overwrite: overwrite);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      setState(() => _saved = text);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.fileSavedOnServer)));
      return;
    }
    final problem = widget.browser.problem ?? FileProblem.failed;
    if (problem != FileProblem.changed) {
      setState(() => _problem = fileProblemText(t, problem));
      return;
    }
    final again = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.changedOnServerTitle),
        content: Text(t.changedOnServerBody(widget.file.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(
            key: const ValueKey('saveAnyway'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.saveAnyway),
          ),
        ],
      ),
    );
    if (again == true) await _save(overwrite: true);
  }

  /// Leaving with unsaved changes asks: they exist nowhere else.
  Future<void> _leave() async {
    final t = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.unsavedTitle),
        content: Text(t.unsavedBody(widget.file.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.keepEditing)),
          FilledButton(
            key: const ValueKey('discardChanges'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.discard),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.file.name}${_dirty ? ' *' : ''}',
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                widget.file.path,
                textDirection: TextDirection.ltr,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.muted, fontFamily: 'JetBrainsMono'),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: FilledButton.icon(
                key: const ValueKey('saveFile'),
                onPressed: _dirty && !_saving ? _save : null,
                icon: _saving
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(t.save),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_problem != null)
                Container(
                  width: double.infinity,
                  color: c.danger.withValues(alpha: 0.1),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    _problem!,
                    key: const ValueKey('editorProblem'),
                    style: TextStyle(color: c.danger),
                  ),
                ),
              Expanded(
                // Code and config read left to right, in either language.
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextField(
                    key: const ValueKey('editorText'),
                    controller: _text,
                    maxLines: null,
                    expands: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.multiline,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13.5, height: 1.45),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
