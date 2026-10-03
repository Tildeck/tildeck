import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../l10n/app_localizations.dart';
import '../settings/device_settings.dart';
import '../terminal/keyword_highlighter.dart';
import '../terminal/session_log.dart';
import '../terminal/terminal_options.dart';
import '../terminal/terminal_themes.dart';
import '../theme.dart';
import '../vault/biometric_unlock.dart';
import '../vault/models.dart';
import '../vault/vault.dart';
import 'account_page.dart';
import 'backup_page.dart';
import 'biometric_settings.dart';
import 'desktop_sidebar.dart';
import 'password_pages.dart';
import 'two_factor.dart';

/// The groups of the settings area.
enum SettingsCategory { general, terminal, security, password, account, backup, shortcuts }

/// Everything that can be set, in one place: on the desktop the groups
/// beside their content, on a phone a list of groups that open as pages.
///
/// The settings of the general, terminal, and security groups are edited
/// together and saved with one bar. The master password and the account
/// are actions, with their own buttons.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.vault,
    required this.settings,
    required this.sync,
    this.initial = SettingsCategory.general,
    this.mobileOptions,
    this.biometrics,
  });

  final Vault vault;
  final DeviceSettingsStore settings;
  final SyncServices sync;
  final SettingsCategory initial;

  /// Biometric unlock on this device; null hides it.
  final BiometricUnlock? biometrics;

  /// The options only a phone has: locking in the background and blocking
  /// screenshots. Null shows them on Android only.
  final bool? mobileOptions;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _draft = SettingsDraft(widget.vault, widget.settings);
  late SettingsCategory _category = widget.initial;

  bool get _mobileOptions => widget.mobileOptions ?? Platform.isAndroid;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  String _title(AppLocalizations t, SettingsCategory c) => switch (c) {
    SettingsCategory.general => t.settingsGeneral,
    SettingsCategory.terminal => t.settingsTerminal,
    SettingsCategory.security => t.settingsSecurity,
    SettingsCategory.password => t.navMasterPassword,
    SettingsCategory.account => t.settingsAccount,
    SettingsCategory.backup => t.settingsBackup,
    SettingsCategory.shortcuts => t.keyboardShortcuts,
  };

  IconData _icon(SettingsCategory c) => switch (c) {
    SettingsCategory.general => Icons.tune_rounded,
    SettingsCategory.terminal => Icons.terminal_rounded,
    SettingsCategory.security => Icons.shield_outlined,
    SettingsCategory.password => Icons.password_rounded,
    SettingsCategory.account => Icons.cloud_sync_outlined,
    SettingsCategory.backup => Icons.save_alt_rounded,
    SettingsCategory.shortcuts => Icons.keyboard_outlined,
  };

  /// What a group shows: its settings, or the page of an action.
  Widget _content(SettingsCategory c) => switch (c) {
    SettingsCategory.general => _SettingsForm(
      title: _title(AppLocalizations.of(context), c),
      draft: _draft,
      content: () => _GeneralSettings(draft: _draft),
    ),
    SettingsCategory.terminal => _SettingsForm(
      title: _title(AppLocalizations.of(context), c),
      draft: _draft,
      content: () => _TerminalSettings(draft: _draft),
    ),
    SettingsCategory.security => _SettingsForm(
      title: _title(AppLocalizations.of(context), c),
      draft: _draft,
      content: () => _SecuritySettings(
        draft: _draft,
        mobileOptions: _mobileOptions,
        sync: widget.sync,
        biometrics: widget.biometrics,
      ),
    ),
    SettingsCategory.password => ChangePasswordPage(services: widget.sync),
    SettingsCategory.account => AccountPage(services: widget.sync),
    SettingsCategory.backup => Scaffold(
      appBar: AppBar(title: Text(_title(AppLocalizations.of(context), c))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [BackupPanel(vault: widget.vault)],
          ),
        ),
      ),
    ),
    SettingsCategory.shortcuts => Scaffold(
      appBar: AppBar(title: Text(_title(AppLocalizations.of(context), c))),
      body: const Align(
        alignment: Alignment.topCenter,
        child: Padding(padding: EdgeInsets.fromLTRB(28, 8, 28, 28), child: ShortcutsList()),
      ),
    ),
  };

  @override
  Widget build(BuildContext context) => isDesktopLayout(context) ? _desktop(context) : _mobile(context);

  Widget _desktop(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 240,
            decoration: BoxDecoration(
              border: BorderDirectional(end: BorderSide(color: c.line)),
            ),
            // The tiles paint their selection on this.
            child: Material(
              color: c.surface,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 8, 16),
                    child: Text(
                      t.settingsTitle,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  for (final category in SettingsCategory.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: ListTile(
                        key: ValueKey('settings-${category.name}'),
                        selected: category == _category,
                        selectedColor: c.ink,
                        selectedTileColor: c.brand.withValues(alpha: 0.14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        leading: Icon(_icon(category), size: 20),
                        title: Text(_title(t, category), style: const TextStyle(fontWeight: FontWeight.w600)),
                        onTap: () => setState(() => _category = category),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: KeyedSubtree(key: ValueKey(_category), child: deskSectionTheme(context, _content(_category))),
          ),
        ],
      ),
    );
  }

  Widget _mobile(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    // Shortcuts need a keyboard: a phone has none to speak of.
    final categories = SettingsCategory.values.where((c) => c != SettingsCategory.shortcuts);
    return Scaffold(
      appBar: AppBar(title: Text(t.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final category in categories)
            ListTile(
              key: ValueKey('settings-${category.name}'),
              leading: Icon(_icon(category), color: c.brand),
              title: Text(_title(t, category), style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _content(category))),
            ),
        ],
      ),
    );
  }
}

/// The settings being edited, before they are saved: this device's and
/// the vault's preferences, compared with what is stored.
class SettingsDraft extends ChangeNotifier {
  SettingsDraft(this.vault, this.store) : device = store.value, prefs = vault.preferences {
    vault.addListener(_stored);
    store.addListener(_stored);
  }

  final Vault vault;
  final DeviceSettingsStore store;
  DeviceSettings device;
  PreferencesEntry prefs;

  bool get dirty => device != store.value || !_samePrefs(prefs, vault.preferences);

  static bool _samePrefs(PreferencesEntry a, PreferencesEntry b) =>
      a.terminalTheme == b.terminalTheme &&
      a.fontSize == b.fontSize &&
      a.autocomplete == b.autocomplete &&
      a.autoLockMinutes == b.autoLockMinutes &&
      a.fontFamily == b.fontFamily &&
      a.lineHeight == b.lineHeight &&
      a.cursorStyle == b.cursorStyle &&
      a.bell == b.bell &&
      a.scrollback == b.scrollback &&
      a.copyOnSelect == b.copyOnSelect &&
      a.autoReconnect == b.autoReconnect &&
      a.highlight == b.highlight &&
      listEquals(a.highlightErrors, b.highlightErrors) &&
      listEquals(a.highlightWarnings, b.highlightWarnings) &&
      listEquals(a.highlightSuccess, b.highlightSuccess);

  /// A change stored elsewhere (another device, through sync) shows here,
  /// unless something is being edited.
  void _stored() {
    if (!dirty) reset();
  }

  void setDevice(DeviceSettings value) {
    device = value;
    notifyListeners();
  }

  void setPrefs(PreferencesEntry value) {
    prefs = value;
    notifyListeners();
  }

  void reset() {
    device = store.value;
    prefs = vault.preferences;
    notifyListeners();
  }

  Future<void> save() async {
    if (!_samePrefs(prefs, vault.preferences)) await vault.put(prefs);
    await store.update(device);
    notifyListeners();
  }

  @override
  void dispose() {
    vault.removeListener(_stored);
    store.removeListener(_stored);
    super.dispose();
  }
}

/// A group of settings on its page, with the save bar at the bottom while
/// something changed.
class _SettingsForm extends StatelessWidget {
  const _SettingsForm({required this.title, required this.draft, required this.content});

  final String title;
  final SettingsDraft draft;

  /// Built again at every change of the draft.
  final Widget Function() content;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListenableBuilder(
                  listenable: draft,
                  builder: (context, _) =>
                      ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 32), children: [content()]),
                ),
              ),
            ),
          ),
          SaveBar(draft: draft),
        ],
      ),
    );
  }
}

/// One bar for the whole settings area: shown while something changed.
class SaveBar extends StatefulWidget {
  const SaveBar({super.key, required this.draft});

  final SettingsDraft draft;

  @override
  State<SaveBar> createState() => _SaveBarState();
}

class _SaveBarState extends State<SaveBar> {
  bool _busy = false;

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.draft.save();
      messenger.showSnackBar(SnackBar(content: Text(t.settingsSaved)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return ListenableBuilder(
      listenable: widget.draft,
      builder: (context, _) {
        if (!widget.draft.dirty) return const SizedBox.shrink();
        return Container(
          key: const ValueKey('saveBar'),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.edit_note_rounded, color: c.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(t.unsavedChanges, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    key: const ValueKey('discardSettings'),
                    onPressed: _busy ? null : widget.draft.reset,
                    child: Text(t.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('saveSettings'),
                    onPressed: _busy ? null : _save,
                    child: Text(t.save),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A setting's label, with its explanation under it.
class _Label extends StatelessWidget {
  const _Label(this.title, [this.help]);

  final String title;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (help != null) ...[const SizedBox(height: 3), Text(help!, style: TextStyle(color: c.muted, fontSize: 13))],
        ],
      ),
    );
  }
}

class _GeneralSettings extends StatelessWidget {
  const _GeneralSettings({required this.draft});

  final SettingsDraft draft;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final device = draft.device;
    String native(String code) => lookupAppLocalizations(Locale(code)).nativeLanguageName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label(t.settingsLanguage, t.thisDeviceOnly),
        SegmentedButton<String>(
          key: const ValueKey('languageChoice'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: '', label: Text(t.languageSystem)),
            ButtonSegment(value: 'he', label: Text(native('he'))),
            ButtonSegment(value: 'en', label: Text(native('en'))),
          ],
          selected: {device.locale?.languageCode ?? ''},
          onSelectionChanged: (v) =>
              draft.setDevice(device.copyWith(locale: () => v.single.isEmpty ? null : Locale(v.single))),
        ),
        _Label(t.settingsTheme, t.thisDeviceOnly),
        SegmentedButton<ThemeMode>(
          key: const ValueKey('themeChoice'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: ThemeMode.system, label: Text(t.themeSystem), icon: const Icon(Icons.contrast)),
            ButtonSegment(
              value: ThemeMode.light,
              label: Text(t.themeLight),
              icon: const Icon(Icons.light_mode_outlined),
            ),
            ButtonSegment(value: ThemeMode.dark, label: Text(t.themeDark), icon: const Icon(Icons.dark_mode_outlined)),
          ],
          selected: {device.themeMode},
          onSelectionChanged: (v) => draft.setDevice(device.copyWith(themeMode: v.single)),
        ),
      ],
    );
  }
}

class _TerminalSettings extends StatelessWidget {
  const _TerminalSettings({required this.draft});

  final SettingsDraft draft;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final prefs = draft.prefs;
    final current = themeById(prefs.terminalTheme);
    final size = prefs.fontSize ?? defaultFontSize;
    final options = TerminalOptions.of(prefs);
    final fonts = terminalFonts();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        TerminalPreview(
          theme: current.theme,
          fontSize: size,
          fontFamily: options.fontFamily,
          lineHeight: options.lineHeight,
        ),
        _Label(t.terminalFontLabel),
        DropdownButtonFormField<String>(
          key: const ValueKey('terminalFont'),
          initialValue: fonts.any((f) => f.family == options.fontFamily) ? options.fontFamily : fonts.first.family,
          isExpanded: true,
          items: [
            for (final f in fonts)
              DropdownMenuItem(
                value: f.family,
                child: Text(f.label, style: TextStyle(fontFamily: f.family)),
              ),
          ],
          onChanged: (v) => draft.setPrefs(prefs.copyWith(fontFamily: v)),
        ),
        _Label(t.fontSizeLabel, t.fontSizeHelp),
        Row(
          children: [
            Expanded(
              child: Slider(
                key: const ValueKey('fontSize'),
                value: size,
                min: minFontSize,
                max: maxFontSize,
                divisions: (maxFontSize - minFontSize).round(),
                label: '${size.round()}',
                onChanged: (v) => draft.setPrefs(prefs.copyWith(fontSize: v.roundToDouble())),
              ),
            ),
            SizedBox(
              width: 32,
              child: Text(
                '${size.round()}',
                key: const ValueKey('fontSizeValue'),
                textAlign: TextAlign.end,
                style: TextStyle(color: c.muted, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        _Label(t.lineHeightLabel),
        Row(
          children: [
            Expanded(
              child: Slider(
                key: const ValueKey('lineHeight'),
                value: options.lineHeight,
                min: minLineHeight,
                max: maxLineHeight,
                divisions: 6,
                label: options.lineHeight.toStringAsFixed(1),
                onChanged: (v) => draft.setPrefs(prefs.copyWith(lineHeight: (v * 10).round() / 10)),
              ),
            ),
            SizedBox(
              width: 32,
              child: Text(
                options.lineHeight.toStringAsFixed(1),
                textAlign: TextAlign.end,
                style: TextStyle(color: c.muted, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        _Label(t.cursorStyleLabel),
        SegmentedButton<String>(
          key: const ValueKey('cursorStyle'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'block', label: Text(t.cursorBlock)),
            ButtonSegment(value: 'underline', label: Text(t.cursorUnderline)),
            ButtonSegment(value: 'bar', label: Text(t.cursorBar)),
          ],
          selected: {prefs.cursorStyle ?? 'block'},
          onSelectionChanged: (v) => draft.setPrefs(prefs.copyWith(cursorStyle: v.single)),
        ),
        _Label(t.bellLabel, t.bellHelp),
        SegmentedButton<BellMode>(
          key: const ValueKey('bellMode'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: BellMode.visual, label: Text(t.bellVisual)),
            ButtonSegment(value: BellMode.sound, label: Text(t.bellSound)),
            ButtonSegment(value: BellMode.none, label: Text(t.bellNone)),
          ],
          selected: {options.bell},
          onSelectionChanged: (v) => draft.setPrefs(prefs.copyWith(bell: v.single.name)),
        ),
        _Label(t.scrollbackLabel, t.scrollbackHelp),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final lines in scrollbackChoices)
              ChoiceChip(
                key: ValueKey('scrollback-$lines'),
                label: Text(t.linesCount(lines)),
                selected: options.scrollback == lines,
                onSelected: (_) => draft.setPrefs(prefs.copyWith(scrollback: lines)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey('copyOnSelect'),
          contentPadding: EdgeInsets.zero,
          value: options.copyOnSelect,
          onChanged: (v) => draft.setPrefs(prefs.copyWith(copyOnSelect: v)),
          title: Text(t.copyOnSelectLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(t.copyOnSelectHelp, style: TextStyle(color: c.muted, fontSize: 13)),
        ),
        if (!Platform.isAndroid && !Platform.isIOS) ...[
          SwitchListTile(
            key: const ValueKey('sessionLogs'),
            contentPadding: EdgeInsets.zero,
            value: draft.device.sessionLogs,
            onChanged: (v) => draft.setDevice(draft.device.copyWith(sessionLogs: v)),
            title: Text(t.sessionLogsLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(t.sessionLogsHelp, style: TextStyle(color: c.muted, fontSize: 13)),
          ),
          if (Platform.isWindows)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('openSessionLogs'),
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(t.openSessionLogs),
                onPressed: () async {
                  final dir = await sessionLogsDirectory();
                  await dir.create(recursive: true);
                  await Process.run('explorer', [dir.path]);
                },
              ),
            ),
        ],
        SwitchListTile(
          key: const ValueKey('highlightSwitch'),
          contentPadding: EdgeInsets.zero,
          value: prefs.highlight ?? true,
          onChanged: (v) => draft.setPrefs(prefs.copyWith(highlight: v)),
          title: Text(t.highlightLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(t.highlightHelp, style: TextStyle(color: c.muted, fontSize: 13)),
        ),
        if (prefs.highlight ?? true)
          for (final (key, label, color, words, set) in [
            (
              'highlightErrors',
              t.highlightErrors,
              KeywordRules.errorColor,
              prefs.highlightErrors ?? KeywordRules.defaultErrors,
              (List<String> v) => prefs.copyWith(highlightErrors: v),
            ),
            (
              'highlightWarnings',
              t.highlightWarnings,
              KeywordRules.warningColor,
              prefs.highlightWarnings ?? KeywordRules.defaultWarnings,
              (List<String> v) => prefs.copyWith(highlightWarnings: v),
            ),
            (
              'highlightSuccess',
              t.highlightSuccess,
              KeywordRules.successColor,
              prefs.highlightSuccess ?? KeywordRules.defaultSuccess,
              (List<String> v) => prefs.copyWith(highlightSuccess: v),
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextFormField(
                key: ValueKey(key),
                initialValue: words.join(', '),
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: label,
                  isDense: true,
                  prefixIcon: Icon(Icons.circle, size: 14, color: color),
                ),
                onChanged: (v) => draft.setPrefs(
                  set([
                    for (final w in v.split(','))
                      if (w.trim().isNotEmpty) w.trim(),
                  ]),
                ),
              ),
            ),
        SwitchListTile(
          key: const ValueKey('autoReconnect'),
          contentPadding: EdgeInsets.zero,
          value: options.autoReconnect,
          onChanged: (v) => draft.setPrefs(prefs.copyWith(autoReconnect: v)),
          title: Text(t.autoReconnectLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(t.autoReconnectHelp, style: TextStyle(color: c.muted, fontSize: 13)),
        ),
        SwitchListTile(
          key: const ValueKey('autocompleteSwitch'),
          contentPadding: EdgeInsets.zero,
          value: prefs.autocomplete ?? true,
          onChanged: (v) => draft.setPrefs(prefs.copyWith(autocomplete: v)),
          title: Text(t.autocompleteLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(t.autocompleteHelp, style: TextStyle(color: c.muted, fontSize: 13)),
        ),
        _Label(t.terminalThemeLabel, t.syncedToAllDevices),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final theme in terminalThemes)
              _ThemeChip(
                theme: theme,
                selected: theme.id == current.id,
                onTap: () => draft.setPrefs(prefs.copyWith(terminalTheme: theme.id)),
              ),
          ],
        ),
      ],
    );
  }
}

class _SecuritySettings extends StatelessWidget {
  const _SecuritySettings({required this.draft, required this.mobileOptions, required this.sync, this.biometrics});

  final SettingsDraft draft;
  final bool mobileOptions;
  final SyncServices sync;
  final BiometricUnlock? biometrics;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final prefs = draft.prefs;
    final device = draft.device;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (biometrics != null) ...[
          const SizedBox(height: 12),
          BiometricSettings(key: const ValueKey('biometric'), biometrics: biometrics!),
        ],
        _Label(t.autoLockLabel, t.autoLockHelp),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final minutes in PreferencesEntry.autoLockChoices)
              ChoiceChip(
                key: ValueKey('autoLock-$minutes'),
                label: Text(t.minutesCount(minutes)),
                selected: (prefs.autoLockMinutes ?? PreferencesEntry.defaultAutoLockMinutes) == minutes,
                onSelected: (_) => draft.setPrefs(prefs.copyWith(autoLockMinutes: minutes)),
              ),
          ],
        ),
        if (mobileOptions) ...[
          _Label(t.backgroundLockLabel, t.thisDeviceOnly),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in BackgroundLock.values)
                ChoiceChip(
                  key: ValueKey('backgroundLock-${choice.name}'),
                  label: Text(switch (choice) {
                    BackgroundLock.immediately => t.backgroundLockImmediately,
                    BackgroundLock.oneMinute => t.backgroundLockOneMinute,
                    BackgroundLock.fiveMinutes => t.backgroundLockFiveMinutes,
                    BackgroundLock.never => t.backgroundLockNever,
                  }),
                  selected: device.backgroundLock == choice,
                  onSelected: (_) => draft.setDevice(device.copyWith(backgroundLock: choice)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            key: const ValueKey('blockScreenshots'),
            contentPadding: EdgeInsets.zero,
            value: device.blockScreenshots,
            onChanged: (v) => draft.setDevice(device.copyWith(blockScreenshots: v)),
            title: Text(t.blockScreenshotsLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(t.blockScreenshotsHelp, style: TextStyle(color: c.muted, fontSize: 13)),
          ),
        ],
        const SizedBox(height: 22),
        Divider(color: c.line),
        const SizedBox(height: 14),
        TwoFactorSettings(key: const ValueKey('twoFactor'), services: sync),
      ],
    );
  }
}

/// A few lines of a shell in the chosen scheme and size.
class TerminalPreview extends StatelessWidget {
  const TerminalPreview({
    super.key,
    required this.theme,
    required this.fontSize,
    this.fontFamily = 'JetBrainsMono',
    this.lineHeight = 1.3,
  });

  final TerminalTheme theme;
  final double fontSize;
  final String fontFamily;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    TextSpan span(String text, Color color, {bool bold = false}) => TextSpan(
      text: text,
      style: TextStyle(color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        key: const ValueKey('terminalPreview'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: theme.background, borderRadius: BorderRadius.circular(14)),
        child: Text.rich(
          TextSpan(
            style: TextStyle(
              fontFamily: fontFamily,
              fontFamilyFallback: const ['JetBrainsMono'],
              fontSize: fontSize,
              height: lineHeight,
              color: theme.foreground,
            ),
            children: [
              span('deploy@web-01', theme.green, bold: true),
              span(':', theme.foreground),
              span('~/app', theme.blue, bold: true),
              span(r'$ ', theme.foreground),
              span('git status\n', theme.foreground),
              span('On branch ', theme.foreground),
              span('main\n', theme.cyan),
              span('modified:   ', theme.red),
              span('config/nginx.conf\n', theme.red),
              span('warning: ', theme.yellow, bold: true),
              span('2 files changed\n', theme.foreground),
              span('deploy@web-01', theme.green, bold: true),
              span(':', theme.foreground),
              span('~/app', theme.blue, bold: true),
              span(r'$ ', theme.foreground),
              span(' ', theme.foreground),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({required this.theme, required this.selected, required this.onTap});

  final NamedTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = theme.theme;
    return InkWell(
      key: ValueKey('theme-${theme.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 156,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: s.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? c.brand : c.line, width: selected ? 3 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    theme.name,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: s.foreground, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
                if (selected) Icon(Icons.check_circle, size: 16, color: s.cursor),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final color in [s.red, s.green, s.yellow, s.blue, s.magenta, s.cyan])
                  Expanded(child: Container(height: 8, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
