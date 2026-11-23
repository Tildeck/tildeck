// One-time secrets for a test run. No test keeps a fixed password,
// passphrase, key, token, or code: each value is drawn here, from the
// system's secure random source, when the test file runs.
import 'dart:convert';
import 'dart:math';

final _random = Random.secure();

/// [length] new random bytes.
List<int> testBytes(int length) => List.generate(length, (_) => _random.nextInt(256));

/// A new secret: 18 random bytes as base64url, 24 characters. Long enough
/// for the master password rules, and never on the common-password list.
String testSecret() => base64Url.encode(testBytes(18));

/// A new TOTP secret in base32, as a server hands it out.
String testTotpSecret() {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  return String.fromCharCodes(List.generate(32, (_) => alphabet.codeUnitAt(_random.nextInt(alphabet.length))));
}

/// Codes this repository's tests once used as fixed values; a generated
/// code never repeats them.
const _onceCommittedCodes = {'123456', '654321'};

/// A new 6-digit code, leading zeros kept.
String testCode() {
  while (true) {
    final code = _random.nextInt(1000000).toString().padLeft(6, '0');
    if (!_onceCommittedCodes.contains(code)) return code;
  }
}

/// A 6-digit code that is never [code].
String otherCode(String code) => ((int.parse(code) + 1 + _random.nextInt(999999)) % 1000000).toString().padLeft(6, '0');

/// One random letter, never `x` (once a fixed value in these tests): for
/// a field that an image shows masked, as a single dot.
String testSecretLetter() {
  const letters = 'abcdefghijklmnopqrstuvwyz';
  return letters[_random.nextInt(letters.length)];
}

/// [code] as a person might type it, with a space in the middle.
String spaced(String code) => '${code.substring(0, 3)} ${code.substring(3)}';

/// Whether [actual] is exactly [expected]. For lists that hold secrets:
/// `expect` on the lists themselves would print the values on a failure.
bool sameValues<T>(List<T>? actual, List<T> expected) =>
    actual != null &&
    actual.length == expected.length &&
    [for (var i = 0; i < actual.length; i++) actual[i] == expected[i]].every((same) => same);
