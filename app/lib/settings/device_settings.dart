import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// When the vault locks after the app goes to the background (Android).
enum BackgroundLock {
  immediately(Duration.zero),
  oneMinute(Duration(minutes: 1)),
  fiveMinutes(Duration(minutes: 5)),
  never(null);

  const BackgroundLock(this.after);

  /// Null: never.
  final Duration? after;
}

/// Settings that belong to this device, not to the vault: they are needed
/// before the vault opens, or make sense only here. Kept in a small file
/// beside the vault; nothing in it is secret.
@immutable
class DeviceSettings {
  const DeviceSettings({
    this.locale,
    this.themeMode = ThemeMode.system,
    this.backgroundLock = BackgroundLock.oneMinute,
    this.blockScreenshots = false,
  });

  /// Null follows the device language.
  final Locale? locale;
  final ThemeMode themeMode;
  final BackgroundLock backgroundLock;

  /// Android: keeps the app out of screenshots, screen recordings, and the
  /// recent apps preview.
  final bool blockScreenshots;

  DeviceSettings copyWith({
    Locale? Function()? locale,
    ThemeMode? themeMode,
    BackgroundLock? backgroundLock,
    bool? blockScreenshots,
  }) => DeviceSettings(
    locale: locale != null ? locale() : this.locale,
    themeMode: themeMode ?? this.themeMode,
    backgroundLock: backgroundLock ?? this.backgroundLock,
    blockScreenshots: blockScreenshots ?? this.blockScreenshots,
  );

  Map<String, Object?> toJson() => {
    'locale': locale?.languageCode,
    'theme': themeMode.name,
    'background_lock': backgroundLock.name,
    'block_screenshots': blockScreenshots,
  };

  /// Unknown or missing values fall back to the defaults: a file from a
  /// newer version never stops the app.
  static DeviceSettings fromJson(Map<String, dynamic> json) {
    T? named<T extends Enum>(List<T> values, Object? name) => values.where((v) => v.name == name).firstOrNull;
    final code = json['locale'];
    return DeviceSettings(
      locale: code == 'he' || code == 'en' ? Locale(code as String) : null,
      themeMode: named(ThemeMode.values, json['theme']) ?? ThemeMode.system,
      backgroundLock: named(BackgroundLock.values, json['background_lock']) ?? BackgroundLock.oneMinute,
      blockScreenshots: json['block_screenshots'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceSettings &&
      other.locale == locale &&
      other.themeMode == themeMode &&
      other.backgroundLock == backgroundLock &&
      other.blockScreenshots == blockScreenshots;

  @override
  int get hashCode => Object.hash(locale, themeMode, backgroundLock, blockScreenshots);
}

/// This device's settings, loaded once and written on every change.
class DeviceSettingsStore extends ChangeNotifier {
  DeviceSettingsStore({this.resolveFile, DeviceSettings initial = const DeviceSettings()}) : _value = initial;

  /// Null keeps the settings in memory only (tests).
  final Future<File> Function()? resolveFile;
  DeviceSettings _value;

  DeviceSettings get value => _value;

  /// Reads the file; a missing or unreadable file leaves the defaults.
  Future<void> load() async {
    final resolve = resolveFile;
    if (resolve == null) return;
    try {
      final file = await resolve();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, dynamic>) {
        _value = DeviceSettings.fromJson(json);
        notifyListeners();
      }
    } on FormatException {
      // A damaged file: the defaults, rewritten at the next change.
    } on FileSystemException {
      // Unreadable: the defaults for this run.
    }
  }

  Future<void> update(DeviceSettings value) async {
    if (value == _value) return;
    _value = value;
    notifyListeners();
    final resolve = resolveFile;
    if (resolve == null) return;
    final file = await resolve();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(value.toJson()), flush: true);
    await temp.rename(file.path);
  }
}
