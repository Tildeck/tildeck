import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'l10n/app_localizations.dart';
import 'platform/biometric.dart';
import 'platform/window_security.dart';
import 'server_check.dart';
import 'settings/device_settings.dart';
import 'ssh/known_hosts.dart';
import 'ssh/ssh_connector.dart';
import 'sync/account_service.dart';
import 'sync/sync_engine.dart';
import 'sync/sync_server.dart';
import 'theme.dart';
import 'ui/account_page.dart';
import 'ui/sessions_page.dart';
import 'ui/vault_gate.dart';
import 'vault/biometric_unlock.dart';
import 'vault/password_rules.dart';
import 'vault/vault.dart';
import 'vault/vault_crypto.dart';

Future<File> _supportFile(String name) async =>
    File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}$name');

class TildeckApp extends StatefulWidget {
  const TildeckApp({
    super.key,
    this.vault,
    this.commonPasswords,
    this.checker,
    this.syncClient,
    this.connector,
    this.showKeyBar,
    this.initialLocale,
    this.initialThemeMode = ThemeMode.system,
    this.settings,
    this.biometricPlatform,
  });

  /// The local vault. Null opens the one in the app support directory.
  final Vault? vault;

  /// Null loads the built-in list from the app's assets.
  final CommonPasswords? commonPasswords;
  final ServerChecker? checker;

  /// The HTTP client for the sync server. Null uses a default one.
  final http.Client? syncClient;

  /// Null connects with host keys kept in the vault.
  final SshConnector? connector;

  /// The on-screen terminal key bar. Null shows it on Android only.
  final bool? showKeyBar;

  /// Null follows the device language.
  final Locale? initialLocale;
  final ThemeMode initialThemeMode;

  /// This device's settings. Null keeps them in the app support directory,
  /// starting from [initialLocale] and [initialThemeMode] until loaded; with
  /// a given [vault] (a test) they stay in memory.
  final DeviceSettingsStore? settings;

  /// The system's biometrics. Null uses the device's, except with a given
  /// [vault] (a test), which then has none.
  final BiometricPlatform? biometricPlatform;

  @override
  State<TildeckApp> createState() => _TildeckAppState();
}

class _TildeckAppState extends State<TildeckApp> {
  late final DeviceSettingsStore _settings =
      widget.settings ??
      DeviceSettingsStore(
        resolveFile: widget.vault == null ? () => _supportFile('settings.json') : null,
        initial: DeviceSettings(locale: widget.initialLocale, themeMode: widget.initialThemeMode),
      );
  late final ServerChecker _checker = widget.checker ?? ServerChecker();
  late final Vault _vault =
      widget.vault ?? Vault(crypto: VaultCrypto.load(), resolveFile: () => _supportFile('vault.json'));
  late final SyncEngine _engine = SyncEngine(
    vault: _vault,
    serverFor: (address) => SyncServer(address, client: widget.syncClient),
  );
  SyncServices? _syncServices;

  /// Built once the common password list has loaded: new master passwords
  /// on the sync screens are checked against it.
  SyncServices _sync(CommonPasswords common) => _syncServices ??= SyncServices(
    vault: _vault,
    engine: _engine,
    accounts: AccountService(vault: _vault, engine: _engine),
    checker: _checker,
    commonPasswords: common,
  );
  late final BiometricUnlock _biometrics = BiometricUnlock(
    _vault,
    widget.biometricPlatform ?? (widget.vault == null ? BiometricPlatform.device : null),
  );
  late final VaultKnownHosts _knownHosts = VaultKnownHosts(_vault);
  late final SshConnector _connector = widget.connector ?? SshConnector(knownHosts: _knownHosts);
  late final Future<CommonPasswords> _commonPasswords = widget.commonPasswords != null
      ? Future.value(widget.commonPasswords)
      : CommonPasswords.load(rootBundle);
  bool _importedLegacyKnownHosts = false;

  @override
  void initState() {
    super.initState();
    _engine; // Syncs from the first unlock on.
    if (_vault.status == VaultStatus.loading) _vault.load();
    _vault.addListener(_onVault);
    _settings.addListener(_onSettings);
    _settings.load();
  }

  /// Applies what the app itself does with this device's settings.
  void _onSettings() {
    setState(() {});
    WindowSecurity.setSecure(_settings.value.blockScreenshots);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    _vault.removeListener(_onVault);
    _engine.dispose();
    if (widget.vault == null) _vault.dispose();
    super.dispose();
  }

  /// Host keys trusted before the vault existed move into it once.
  void _onVault() {
    if (_vault.status != VaultStatus.unlocked || _importedLegacyKnownHosts || widget.vault != null) return;
    _importedLegacyKnownHosts = true;
    _supportFile('known_hosts.json').then(_knownHosts.importLegacyFile);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _settings.value.themeMode,
      locale: _settings.value.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: FutureBuilder<CommonPasswords>(
        future: _commonPasswords,
        builder: (context, snapshot) {
          final common = snapshot.data;
          if (common == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          return VaultGate(
            vault: _vault,
            commonPasswords: common,
            sync: _sync(common),
            settings: _settings,
            biometrics: _biometrics,
            unlocked: (context) {
              final current = Localizations.localeOf(context);
              final dark = Theme.of(context).brightness == Brightness.dark;
              return SessionsPage(
                vault: _vault,
                connector: _connector,
                sync: _sync(common),
                showKeyBar: widget.showKeyBar ?? Platform.isAndroid,
                settings: _settings,
                biometrics: _biometrics,
                onToggleLocale: () => _settings.update(
                  _settings.value.copyWith(
                    locale: () => current.languageCode == 'he' ? const Locale('en') : const Locale('he'),
                  ),
                ),
                onToggleTheme: () =>
                    _settings.update(_settings.value.copyWith(themeMode: dark ? ThemeMode.light : ThemeMode.dark)),
              );
            },
          );
        },
      ),
    );
  }
}
