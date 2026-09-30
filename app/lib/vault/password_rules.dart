import 'package:flutter/services.dart';

/// Why a master password is refused (docs/security-model.md).
enum PasswordProblem { tooShort, common }

const minMasterPasswordLength = 12;

/// The built-in list of common passwords that are long enough to pass the
/// length rule.
class CommonPasswords {
  CommonPasswords(this._passwords);

  final Set<String> _passwords;

  static Future<CommonPasswords> load(AssetBundle bundle) async {
    final text = await bundle.loadString('assets/security/common-passwords.txt');
    return CommonPasswords({
      for (final line in text.split('\n'))
        if (line.isNotEmpty && !line.startsWith('#')) line.trim(),
    });
  }

  bool contains(String password) => _passwords.contains(password.toLowerCase());
}

PasswordProblem? checkMasterPassword(String password, CommonPasswords common) {
  if (password.runes.length < minMasterPasswordLength) return PasswordProblem.tooShort;
  if (common.contains(password)) return PasswordProblem.common;
  return null;
}
