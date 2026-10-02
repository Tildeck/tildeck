import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps the app out of screenshots and the recent apps preview (Android).
/// Elsewhere it does nothing.
class WindowSecurity {
  static const _channel = MethodChannel('tildeck/window');

  static bool get supported => Platform.isAndroid;

  static Future<void> setSecure(bool secure) async {
    if (!supported) return;
    await _channel.invokeMethod<void>('setSecure', secure);
  }
}
