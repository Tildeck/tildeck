import 'dart:convert';

import 'package:dartssh2/dartssh2.dart' show SSHClient;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../l10n/app_localizations.dart';
import '../ssh/certificates.dart';
import '../ssh/keys.dart';
import '../ssh/local_files.dart';
import '../ssh/ppk.dart';
import '../ssh/ssh_connector.dart';
import '../theme.dart';
import '../vault/models.dart';
import '../vault/vault.dart';
import 'desktop_sidebar.dart' show isDesktopLayout;
import 'known_hosts_page.dart';
import 'terminal_panel.dart' show connectProblemText;

/// Opens an authenticated connection to a saved host, as a session would.
typedef HostConnect = Future<SSHClient> Function(BuildContext context, HostEntry host);

/// A key entry for [pem], with what can be read from it kept alongside.
/// Null when it is not a key or the passphrase does not open it.
KeyEntry? keyEntryFor({required String id, required String name, required String pem, String? passphrase}) {
  final info = readKey(pem, passphrase: passphrase, comment: name);
  if (info == null) return null;
  return KeyEntry(
    id: id,
    name: name,
    privateKey: pem.trim(),
    passphrase: (passphrase?.isEmpty ?? true) ? null : passphrase,
    keyType: info.type,
    fingerprint: info.fingerprint,
    publicKey: info.publicKey,
  );
}

/// Adds a private key to the vault, pasted or from a file; returns its id.
Future<String?> showKeyEditor(BuildContext context, Vault vault, {LocalFiles files = const DeviceFiles()}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _ImportKey(vault: vault, files: files),
    );

/// Makes a new key in the vault; returns its id.
Future<String?> showKeyGenerator(BuildContext context, Vault vault) => showDialog<String>(
  context: context,
  builder: (_) => _GenerateKey(vault: vault),
);

class KeysPage extends StatefulWidget {
  const KeysPage({super.key, required this.vault, this.connect, this.files = const DeviceFiles()});

  final Vault vault;

  /// For installing a key on a saved host; null hides it.
  final HostConnect? connect;
  final LocalFiles files;

  @override
  State<KeysPage> createState() => _KeysPageState();
}

class _KeysPageState extends State<KeysPage> {
  Vault get vault => widget.vault;

  /// Keys saved before their public half was kept: read once, here.
  final _read = <String, KeyInfo?>{};

  KeyInfo? _info(KeyEntry key) {
    if (key.publicKey != null) {
      return KeyInfo(type: key.keyType ?? '', fingerprint: key.fingerprint ?? '', publicKey: key.publicKey!);
    }
    return _read.putIfAbsent(key.id, () => readKey(key.privateKey, passphrase: key.passphrase, comment: key.name));
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _add() async {
    final t = AppLocalizations.of(context);
    // A sheet from the bottom on a phone; a small dialog on the desktop.
    Widget choices(BuildContext context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('generateKey'),
            leading: const Icon(Icons.auto_awesome_outlined),
            title: Text(t.generateKey),
            onTap: () => Navigator.pop(context, 'generate'),
          ),
          ListTile(
            key: const ValueKey('importKey'),
            leading: const Icon(Icons.file_download_outlined),
            title: Text(t.importKey),
            onTap: () => Navigator.pop(context, 'import'),
          ),
        ],
      ),
    );
    final choice = isDesktopLayout(context)
        ? await showDialog<String>(
            context: context,
            builder: (context) => Dialog(child: SizedBox(width: 380, child: choices(context))),
          )
        : await showModalBottomSheet<String>(context: context, builder: choices);
    if (!mounted || choice == null) return;
    if (choice == 'generate') {
      await showKeyGenerator(context, vault);
    } else {
      await showKeyEditor(context, vault, files: widget.files);
    }
  }

  Future<void> _install(KeyEntry key, KeyInfo info) async {
    final installed = await showDialog<String>(
      context: context,
      builder: (_) => _InstallKey(vault: vault, publicKey: info.publicKey, connect: widget.connect!),
    );
    if (installed != null && mounted) _message(AppLocalizations.of(context).keyInstalled(installed));
  }

  Future<void> _export(KeyEntry key) async {
    final t = AppLocalizations.of(context);
    final passphrase = await showDialog<String>(context: context, builder: (_) => const _ExportKey());
    if (passphrase == null || !mounted) return;
    final pem = exportKey(key.privateKey, passphrase: key.passphrase, newPassphrase: passphrase);
    final name = _fileName(key);
    final file = await widget.files.downloadTarget(name);
    await file.writeAsString('$pem\n');
    final kept = await widget.files.keep(file, name);
    if (kept != null && mounted) _message(t.keyExported(kept));
  }

  /// Like ssh-keygen's: id_ed25519, id_rsa, and the key's name after it.
  static String _fileName(KeyEntry key) {
    final kind = switch (key.keyType) {
      'ssh-ed25519' => 'ed25519',
      'ssh-rsa' => 'rsa',
      final other => other?.replaceAll(RegExp('[^a-z0-9]'), '') ?? 'key',
    };
    final name = key.name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    return name.isEmpty ? 'id_$kind' : 'id_${kind}_$name';
  }

  /// [details] and, under them, what the key's certificate allows.
  Widget _withCertificate(BuildContext context, KeyEntry key, Widget details) {
    final certificate = key.certificate == null ? null : readCertificate(key.certificate!);
    if (certificate == null) return details;
    final t = AppLocalizations.of(context);
    final c = context.colors;
    // With the year: an expiry date without one is ambiguous.
    final date = DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).format;
    // Usernames keep their own order inside a Hebrew sentence.
    final principals = certificate.principals.isEmpty
        ? t.certificateAnyUser
        : '\u2066${certificate.principals.join(', ')}\u2069';
    final expired = certificate.expiredAt(DateTime.now());
    final text = expired
        ? t.certificateExpired(date(certificate.validBefore!.toLocal()))
        : certificate.validBefore == null
        ? t.certificateForever(principals)
        : t.certificateValid(principals, date(certificate.validBefore!.toLocal()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        details,
        const SizedBox(height: 2),
        Text(
          text,
          key: ValueKey('certificate-${key.name}'),
          style: TextStyle(fontSize: 12, color: expired ? c.danger : c.success),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    // On the desktop: a button in the header, not one floating over the
    // list, and the sidebar has the known hosts.
    final desktop = isDesktopLayout(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.keysTitle),
        actions: [
          if (desktop)
            FilledButton.icon(
              key: const ValueKey('addKey'),
              icon: const Icon(Icons.add, size: 18),
              label: Text(t.addKey),
              onPressed: _add,
            )
          else
            TextButton.icon(
              key: const ValueKey('openKnownHosts'),
              icon: const Icon(Icons.verified_user_outlined, size: 18),
              label: Text(t.knownHostsTitle),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => KnownHostsPage(vault: vault))),
            ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: desktop
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('addKey'),
              icon: const Icon(Icons.add),
              label: Text(t.addKey),
              onPressed: _add,
            ),
      body: ListenableBuilder(
        listenable: vault,
        builder: (context, _) {
          final keys = vault.keys;
          if (keys.isEmpty) {
            return Center(
              child: Text(t.noKeysYet, style: TextStyle(color: c.muted)),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              for (final key in keys)
                Builder(
                  builder: (context) {
                    final info = _info(key);
                    return ListTile(
                      key: ValueKey('key-${key.name}'),
                      leading: Icon(Icons.key, color: c.brand),
                      title: Text(key.name),
                      subtitle: info == null
                          ? Text(t.keyUnreadable, style: TextStyle(color: c.danger))
                          : _withCertificate(
                              context,
                              key,
                              Text(
                                // The whole fingerprint: it is what is compared.
                                '${info.type}\n${info.fingerprint}',
                                textDirection: TextDirection.ltr,
                                textAlign: Directionality.of(context) == TextDirection.rtl
                                    ? TextAlign.right
                                    : TextAlign.left,
                                style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11.5, height: 1.4),
                              ),
                            ),
                      trailing: PopupMenuButton<String>(
                        key: ValueKey('keyMenu-${key.name}'),
                        onSelected: (action) async {
                          switch (action) {
                            case 'copy':
                              await Clipboard.setData(ClipboardData(text: info!.publicKey));
                              _message(t.publicKeyCopied);
                            case 'install':
                              await _install(key, info!);
                            case 'export':
                              await _export(key);
                            case 'certificate':
                              await showDialog<void>(
                                context: context,
                                builder: (_) => _AddCertificate(vault: vault, keyEntry: key, files: widget.files),
                              );
                            case 'removeCertificate':
                              await vault.put(key.withCertificate(null));
                            case 'delete':
                              if (vault.hosts.any((h) => h.keyId == key.id) ||
                                  vault.groups.any((g) => g.keyId == key.id)) {
                                _message(t.keyInUse);
                                return;
                              }
                              await vault.delete(key.id);
                          }
                        },
                        itemBuilder: (_) => [
                          if (info != null) ...[
                            PopupMenuItem(
                              key: const ValueKey('copyPublicKey'),
                              value: 'copy',
                              child: Text(t.copyPublicKey),
                            ),
                            if (widget.connect != null)
                              PopupMenuItem(
                                key: const ValueKey('installKey'),
                                value: 'install',
                                child: Text(t.installKey),
                              ),
                            PopupMenuItem(key: const ValueKey('exportKey'), value: 'export', child: Text(t.exportKey)),
                            if (key.certificate == null)
                              PopupMenuItem(
                                key: const ValueKey('addCertificate'),
                                value: 'certificate',
                                child: Text(t.addCertificate),
                              )
                            else
                              PopupMenuItem(
                                key: const ValueKey('removeCertificate'),
                                value: 'removeCertificate',
                                child: Text(t.removeCertificate),
                              ),
                          ],
                          PopupMenuItem(value: 'delete', child: Text(t.deleteAction)),
                        ],
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _GenerateKey extends StatefulWidget {
  const _GenerateKey({required this.vault});

  final Vault vault;

  @override
  State<_GenerateKey> createState() => _GenerateKeyState();
}

class _GenerateKeyState extends State<_GenerateKey> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  var _kind = KeyKind.ed25519;
  var _working = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _working = true);
    final name = _name.text.trim();
    final pem = switch (_kind) {
      KeyKind.ed25519 => generateEd25519(widget.vault.crypto.sodium, name),
      KeyKind.rsa4096 => await generateRsa4096(name),
    };
    final entry = keyEntryFor(id: widget.vault.newId(), name: name, pem: pem)!;
    await widget.vault.put(entry);
    if (mounted) Navigator.pop(context, entry.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return AlertDialog(
      title: Text(t.generateKey),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('keyName'),
                controller: _name,
                autofocus: true,
                validator: (v) => (v ?? '').trim().isEmpty ? t.fieldRequired : null,
                decoration: InputDecoration(labelText: t.keyNameLabel, hintText: t.keyNameHint),
              ),
              const SizedBox(height: 14),
              SegmentedButton<KeyKind>(
                key: const ValueKey('keyKind'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: KeyKind.ed25519, label: Text('Ed25519')),
                  ButtonSegment(value: KeyKind.rsa4096, label: Text('RSA 4096')),
                ],
                selected: {_kind},
                onSelectionChanged: _working ? null : (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 8),
              Text(
                _kind == KeyKind.ed25519 ? t.keyEd25519Help : t.keyRsaHelp,
                style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _working ? null : () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          key: const ValueKey('generate'),
          onPressed: _working ? null : _generate,
          child: _working
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(t.generateButton),
        ),
      ],
    );
  }
}

class _ImportKey extends StatefulWidget {
  const _ImportKey({required this.vault, required this.files});

  final Vault vault;
  final LocalFiles files;

  @override
  State<_ImportKey> createState() => _ImportKeyState();
}

class _ImportKeyState extends State<_ImportKey> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _pem = TextEditingController();
  final _passphrase = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    for (final c in [_name, _pem, _passphrase]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fromFile() async {
    final picked = await widget.files.pickToUpload();
    if (picked.isEmpty) return;
    final file = picked.first;
    final text = await utf8.decoder.bind(file.read()).join();
    setState(() {
      _pem.text = text.trim();
      if (_name.text.trim().isEmpty) _name.text = file.name;
      _problem = null;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    var pem = _pem.text;
    var passphrase = _passphrase.text;
    // A PuTTY key is turned into an OpenSSH one; the vault keeps it, so it
    // needs no passphrase of its own there.
    if (looksLikePpk(pem)) {
      try {
        pem = ppkToOpenSsh(pem, passphrase: passphrase);
        passphrase = '';
      } on PpkException catch (e) {
        setState(
          () => _problem = switch (e.problem) {
            PpkProblem.passphraseNeeded => t.ppkPassphraseNeeded,
            PpkProblem.wrongPassphrase => t.ppkWrongPassphrase,
            PpkProblem.unsupported => t.ppkUnsupported,
            PpkProblem.malformed => t.keyUnreadable,
          },
        );
        return;
      }
    }
    final entry = keyEntryFor(id: widget.vault.newId(), name: _name.text.trim(), pem: pem, passphrase: passphrase);
    if (entry == null) {
      setState(() => _problem = t.keyUnreadable);
      return;
    }
    await widget.vault.put(entry);
    if (mounted) Navigator.pop(context, entry.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    String? required(String? v) => (v ?? '').trim().isEmpty ? t.fieldRequired : null;
    return AlertDialog(
      title: Text(t.importKey),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('keyName'),
                  controller: _name,
                  validator: required,
                  decoration: InputDecoration(labelText: t.keyNameLabel, hintText: t.keyNameHint),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('keyPem'),
                  controller: _pem,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
                  minLines: 4,
                  maxLines: 8,
                  autocorrect: false,
                  enableSuggestions: false,
                  validator: required,
                  onChanged: (_) => setState(() => _problem = null),
                  decoration: InputDecoration(
                    labelText: t.privateKeyLabel,
                    hintText: t.privateKeyHint,
                    alignLabelWithHint: true,
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('keyFromFile'),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(t.keyFromFile),
                    onPressed: _fromFile,
                  ),
                ),
                TextFormField(
                  key: const ValueKey('keyPassphrase'),
                  controller: _passphrase,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  onChanged: (_) => setState(() => _problem = null),
                  decoration: InputDecoration(labelText: t.passphraseLabel),
                ),
                if (_problem != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _problem!,
                    key: const ValueKey('keyProblem'),
                    style: TextStyle(color: c.danger),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(key: const ValueKey('saveKey'), onPressed: _save, child: Text(t.save)),
      ],
    );
  }
}

/// Asks for a passphrase for an exported key file. Returns it (empty for
/// none), or null when cancelled.
class _ExportKey extends StatefulWidget {
  const _ExportKey();

  @override
  State<_ExportKey> createState() => _ExportKeyState();
}

class _ExportKeyState extends State<_ExportKey> {
  final _passphrase = TextEditingController();

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return AlertDialog(
      title: Text(t.exportKey),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.exportKeyHelp, style: TextStyle(color: c.muted, height: 1.4)),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('exportPassphrase'),
              controller: _passphrase,
              obscureText: true,
              autofocus: true,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: t.exportPassphrase),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          key: const ValueKey('saveExport'),
          onPressed: () => Navigator.pop(context, _passphrase.text),
          child: Text(t.save),
        ),
      ],
    );
  }
}

/// Adds a public key to authorized_keys on a saved host. Returns the
/// host's name once installed.
class _InstallKey extends StatefulWidget {
  const _InstallKey({required this.vault, required this.publicKey, required this.connect});

  final Vault vault;
  final String publicKey;
  final HostConnect connect;

  @override
  State<_InstallKey> createState() => _InstallKeyState();
}

class _InstallKeyState extends State<_InstallKey> {
  late final _hosts = widget.vault.hosts.where((h) => h.isSsh).toList();
  late String? _hostId = _hosts.isEmpty ? null : _hosts.first.id;
  var _working = false;
  String? _problem;

  Future<void> _install() async {
    final host = widget.vault.entry<HostEntry>(_hostId);
    if (host == null) return;
    final t = AppLocalizations.of(context);
    setState(() {
      _working = true;
      _problem = null;
    });
    SSHClient? client;
    try {
      client = await widget.connect(context, host);
      final out = utf8.decode(await client.run(installKeyCommand(widget.publicKey)), allowMalformed: true);
      if (!out.contains('tildeck-key-installed')) throw StateError(out.trim());
      if (mounted) Navigator.pop(context, host.name);
    } on ConnectException catch (e) {
      if (mounted) setState(() => _problem = connectProblemText(t, e.problem));
    } catch (_) {
      if (mounted) setState(() => _problem = t.keyInstallFailed);
    } finally {
      client?.close();
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return AlertDialog(
      title: Text(t.installKey),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.installKeyHelp, style: TextStyle(color: c.muted, height: 1.4)),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: const ValueKey('installHost'),
              initialValue: _hostId,
              isExpanded: true,
              decoration: InputDecoration(labelText: t.installKeyOn),
              items: [for (final h in _hosts) DropdownMenuItem(value: h.id, child: Text(h.name))],
              onChanged: _working ? null : (v) => setState(() => _hostId = v),
            ),
            if (_problem != null) ...[
              const SizedBox(height: 10),
              Text(
                _problem!,
                key: const ValueKey('installProblem'),
                style: TextStyle(color: c.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _working ? null : () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          key: const ValueKey('installKeyButton'),
          onPressed: _working || _hostId == null ? null : _install,
          child: _working
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(t.installKeyButton),
        ),
      ],
    );
  }
}

/// Adds an OpenSSH certificate to a key, pasted or from its -cert.pub file.
class _AddCertificate extends StatefulWidget {
  const _AddCertificate({required this.vault, required this.keyEntry, required this.files});

  final Vault vault;
  final KeyEntry keyEntry;
  final LocalFiles files;

  @override
  State<_AddCertificate> createState() => _AddCertificateState();
}

class _AddCertificateState extends State<_AddCertificate> {
  final _text = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _fromFile() async {
    final picked = await widget.files.pickToUpload();
    if (picked.isEmpty) return;
    final text = await utf8.decoder.bind(picked.first.read()).join();
    setState(() {
      _text.text = text.trim();
      _problem = null;
    });
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final key = widget.keyEntry;
    final certificate = readCertificate(_text.text);
    if (certificate == null) {
      setState(() => _problem = t.certificateUnreadable);
      return;
    }
    if (!certificateMatches(certificate, key.privateKey, passphrase: key.passphrase)) {
      setState(() => _problem = t.certificateOtherKey);
      return;
    }
    await widget.vault.put(key.withCertificate(_text.text.trim()));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return AlertDialog(
      title: Text(t.addCertificate),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.certificateHelp, style: TextStyle(color: c.muted, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('certificateText'),
              controller: _text,
              minLines: 3,
              maxLines: 6,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
              onChanged: (_) => setState(() => _problem = null),
              decoration: InputDecoration(labelText: t.certificateLabel, alignLabelWithHint: true),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('certificateFromFile'),
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(t.keyFromFile),
                onPressed: _fromFile,
              ),
            ),
            if (_problem != null)
              Text(
                _problem!,
                key: const ValueKey('certificateProblem'),
                style: TextStyle(color: c.danger),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(key: const ValueKey('saveCertificate'), onPressed: _save, child: Text(t.save)),
      ],
    );
  }
}
