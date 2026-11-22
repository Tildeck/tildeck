// The one-time key files that scripts/verify.sh makes for each test run with
// puttygen (make_test_key_files there): PuTTY key files in every format the
// client reads, each with puttygen's own fingerprint of it (<name>.fp), and
// a passphrase-protected OpenSSH key. The encrypted ones share one random
// passphrase. No key or passphrase is kept in the repository.
//
// Without them, the tests that read them are skipped, so a plain
// `flutter test` still runs everything else. With
// TILDECK_REQUIRE_KEY_FILE_TESTS set, as scripts/verify.sh and CI set it, or
// with only part of the environment, those tests run and fail on anything
// missing.
import 'dart:io';

final _env = Platform.environment;
final _dir = _env['TILDECK_TEST_KEY_FILES'];
final _passphrase = _env['TILDECK_TEST_KEY_PASSPHRASE'];
final _required = _env['TILDECK_REQUIRE_KEY_FILE_TESTS'] != null;

/// The skip reason for a test that reads generated key files, or null when
/// it runs. With only part of the environment, or a directory that does not
/// exist, the test file fails to load, so no test passes without its files.
final String? keyFilesSkip = () {
  if (_dir == null && _passphrase == null && !_required) {
    return 'no generated key files in the environment (scripts/verify.sh --area app makes them)';
  }
  final dir = _dir;
  if (dir == null || dir.isEmpty || (_passphrase ?? '').isEmpty || !Directory(dir).existsSync()) {
    throw StateError(
      'The generated key files are set up only in part: TILDECK_TEST_KEY_FILES (an existing directory) '
      'and TILDECK_TEST_KEY_PASSPHRASE are both needed; scripts/verify.sh sets them.',
    );
  }
  return null;
}();

/// The text of the generated file [name].
String keyFile(String name) {
  final dir = _dir;
  if (dir == null || dir.isEmpty) {
    throw StateError('TILDECK_TEST_KEY_FILES is not set; scripts/verify.sh sets it.');
  }
  final file = File('$dir/$name');
  if (!file.existsSync()) throw StateError('The generated key file $name is missing from $dir.');
  return file.readAsStringSync();
}

/// The passphrase of the generated encrypted keys.
String get keyFilePassphrase {
  final passphrase = _passphrase;
  if (passphrase == null || passphrase.isEmpty) {
    throw StateError('TILDECK_TEST_KEY_PASSPHRASE is not set; scripts/verify.sh sets it.');
  }
  return passphrase;
}

/// puttygen's fingerprint of the generated key [name]: its key type, its
/// size in bits, and its SHA256 fingerprint.
({String type, String fingerprint}) keyFileFingerprint(String name) {
  final parts = keyFile('$name.fp').trim().split(' ');
  return (type: parts.first, fingerprint: parts.last);
}
