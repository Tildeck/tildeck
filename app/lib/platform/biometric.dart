import 'dart:io';

import 'package:flutter/services.dart';

/// Why the system did not give the key.
enum BiometricFailure {
  /// The user cancelled, or chose the master password instead.
  cancelled,

  /// The system closed the prompt, not the user: the app left the screen,
  /// or the prompt was opened while it was not in front. Ask again later.
  interrupted,

  /// The key is gone: a new fingerprint was enrolled (Android), or the
  /// Windows Hello key was deleted. Biometric unlock must be turned on again.
  invalidated,

  /// Biometrics are not set up on this device, or not available now.
  unavailable,
  failed,
}

class BiometricException implements Exception {
  const BiometricException(this.failure, [this.message]);

  final BiometricFailure failure;
  final String? message;

  @override
  String toString() => 'BiometricException(${failure.name}${message == null ? '' : ': $message'})';
}

/// The words of the Android prompt; Windows Hello shows its own.
class BiometricPromptText {
  const BiometricPromptText({required this.title, required this.subtitle, required this.cancel});

  final String title;
  final String subtitle;
  final String cancel;

  Map<String, String> toMap() => {'title': title, 'subtitle': subtitle, 'cancel': cancel};
}

/// What the operating system does for biometric unlock
/// (docs/security-model.md, "Biometric unlock").
abstract class BiometricPlatform {
  /// Android keeps `BK` itself, encrypted by a Keystore key; Windows derives
  /// it from a Windows Hello signature.
  bool get keepsKey;

  Future<bool> available();

  /// Android: encrypts [key] with a new Keystore key, after a biometric
  /// check; returns its nonce and ciphertext.
  Future<(Uint8List, Uint8List)> protect(String vaultId, Uint8List key, BiometricPromptText text);

  /// Android: decrypts what [protect] returned, after a biometric check.
  Future<Uint8List> release(String vaultId, Uint8List nonce, Uint8List ciphertext, BiometricPromptText text);

  /// Windows: creates the vault's Hello key and signs [challenge] with it.
  Future<Uint8List> enrollSigner(String vaultId, Uint8List challenge);

  /// Windows: signs [challenge] with the vault's Hello key.
  Future<Uint8List> sign(String vaultId, Uint8List challenge);

  /// Deletes the vault's Keystore or Hello key.
  Future<void> remove(String vaultId);

  /// The platform's own, or null where there is none.
  static BiometricPlatform? get device =>
      Platform.isAndroid || Platform.isWindows ? const ChannelBiometricPlatform() : null;
}

/// The native side: MainActivity.kt on Android, the runner on Windows.
class ChannelBiometricPlatform implements BiometricPlatform {
  const ChannelBiometricPlatform();

  static const _channel = MethodChannel('tildeck/biometric');

  @override
  bool get keepsKey => Platform.isAndroid;

  Future<T> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      final result = await _channel.invokeMethod<T>(method, args);
      if (result == null && null is! T) throw const BiometricException(BiometricFailure.failed, 'no result');
      return result as T;
    } on PlatformException catch (e) {
      final failure = switch (e.code) {
        'cancelled' => BiometricFailure.cancelled,
        'interrupted' => BiometricFailure.interrupted,
        'invalidated' || 'not_found' => BiometricFailure.invalidated,
        'unavailable' => BiometricFailure.unavailable,
        _ => BiometricFailure.failed,
      };
      throw BiometricException(failure, e.message);
    } on MissingPluginException {
      throw const BiometricException(BiometricFailure.unavailable);
    }
  }

  @override
  Future<bool> available() async {
    try {
      return await _call<String>('support') == 'available';
    } on BiometricException {
      return false;
    }
  }

  @override
  Future<(Uint8List, Uint8List)> protect(String vaultId, Uint8List key, BiometricPromptText text) async {
    final result = await _call<Map<Object?, Object?>>('enroll', {'vaultId': vaultId, 'key': key, ...text.toMap()});
    return (result['nonce']! as Uint8List, result['ciphertext']! as Uint8List);
  }

  @override
  Future<Uint8List> release(String vaultId, Uint8List nonce, Uint8List ciphertext, BiometricPromptText text) =>
      _call<Uint8List>('obtain', {'vaultId': vaultId, 'nonce': nonce, 'ciphertext': ciphertext, ...text.toMap()});

  @override
  Future<Uint8List> enrollSigner(String vaultId, Uint8List challenge) =>
      _call<Uint8List>('enroll', {'vaultId': vaultId, 'challenge': challenge});

  @override
  Future<Uint8List> sign(String vaultId, Uint8List challenge) =>
      _call<Uint8List>('obtain', {'vaultId': vaultId, 'challenge': challenge});

  @override
  Future<void> remove(String vaultId) => _call<void>('remove', {'vaultId': vaultId});
}
