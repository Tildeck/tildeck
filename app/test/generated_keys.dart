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

/// The key files and passphrase these tests once kept in the repository.
/// They are public now, so key files with one of these fingerprints, or
/// that passphrase, are refused: every run must bring new ones.
const _onceCommittedFingerprints = {
  'SHA256:LnelfUHA02MMwH8DiGpqBCQLWh3z3ywwt+jG3u+olto',
  'SHA256:TYoTdmyWDVJWiNV4xdfAhCD3dbbOVhm0i5LWouH844c',
  'SHA256:ARimebReL2RtUzeDdL/dV6gj5UK0sPD14QYJw5MZS84',
  'SHA256:ifKjLWKwpt2cBgm+tYdBQBMhpjqAmGijAYKPUytobcs',
  'SHA256:9D3CxmW0LTg+MuvSOJ5BP7C6iCzHHQi2T81MVcKOGRs',
  'SHA256:RgmQitQMPu64vUNDLdawyzBh46N6VqjctmkDBQacqwo',
  'SHA256:3rN64P85BCWdgRiINvdJyJz6CDidXzwgsk/4cUPh9iA',
  'SHA256:jhN19w733uwGARjOgEqoUoPIKWS3XzkKTamtVmjLCd0',
  'SHA256:tT2YbGADp2K9974keuRJAKm9ZKkV8nkILk2KDx5l6vI',
};
const _onceCommittedPassphrase = 'tildeck-test';

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
  final published =
      _passphrase == _onceCommittedPassphrase ||
      Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.fp'))
          .any((f) => _onceCommittedFingerprints.contains(f.readAsStringSync().trim().split(' ').last));
  if (published) {
    throw StateError(
      'These key files or this passphrase were once kept in the repository and are public; '
      'generate new ones (scripts/verify.sh does).',
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
