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
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

/// The key files and passphrase these tests once kept in the repository
/// (the passphrase as its SHA-256 only). They are public now, so key files
/// with one of these fingerprints, or that passphrase, are refused: every
/// run must bring new ones.
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
const _onceCommittedPassphraseSha256 = '7f283d1d36ccf44c658ab59789ad102ba64353569dd374a010a8613b093a9a01';

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
  if (_sha256Hex(utf8.encode(_passphrase!)) == _onceCommittedPassphraseSha256) {
    throw StateError('This passphrase was once kept in the repository and is public; use a new one.');
  }
  // Every file but the .fp ones is a key the tests may read. Its fingerprint
  // comes from the key file itself, so a stale .fp beside an old key cannot
  // hide it, and a file that cannot be read as a key is refused, not skipped.
  for (final file in Directory(dir).listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (name.endsWith('.fp')) continue;
    final String fingerprint;
    try {
      fingerprint = _fingerprintOf(file.readAsStringSync());
    } catch (_) {
      // Only the name: the error itself may quote the file's content.
      throw StateError('$name in the generated key files is not a key file these tests can read.');
    }
    if (_onceCommittedFingerprints.contains(fingerprint)) {
      throw StateError('The key in $name was once kept in the repository and is public; generate new key files.');
    }
    final fp = File('$dir/${name.replaceFirst(RegExp(r'\.ppk$'), '')}.fp');
    if (fp.existsSync() && fp.readAsStringSync().trim().split(' ').last != fingerprint) {
      throw StateError("The fingerprint beside $name is not that key's; generate the key files again.");
    }
  }
  return null;
}();

String _sha256Hex(List<int> bytes) =>
    pc.SHA256Digest().process(Uint8List.fromList(bytes)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// The SHA256 fingerprint of the public key in a PuTTY key file or an
/// OpenSSH private key file, worked out here with pointycastle, not with
/// the client's own key code. Throws for anything else, and for a PuTTY
/// file with more or fewer than one public key.
String _fingerprintOf(String text) {
  late final Uint8List blob;
  // Split and trimmed as the client does (LineSplitter: LF, CR, or CRLF).
  final lines = const LineSplitter().convert(text.trim()).map((l) => l.trim()).toList();
  if (lines.first.startsWith('PuTTY-User-Key-File-')) {
    final headers = [
      for (var i = 0; i < lines.length; i++)
        if (lines[i].startsWith('Public-Lines: ')) i,
    ];
    if (headers.length != 1) throw const FormatException('not one public key');
    final at = headers.single;
    final count = int.parse(lines[at].substring('Public-Lines: '.length));
    blob = base64.decode(lines.sublist(at + 1, at + 1 + count).join());
  } else if (lines.first == '-----BEGIN OPENSSH PRIVATE KEY-----') {
    final body = base64.decode(lines.skip(1).takeWhile((l) => !l.startsWith('-----END')).join());
    // "openssh-key-v1\0", then cipher, KDF, and KDF options as strings, the
    // number of keys, and the first public key as a string.
    final data = ByteData.sublistView(body);
    var offset = 'openssh-key-v1'.length + 1;
    for (var i = 0; i < 3; i++) {
      offset += 4 + data.getUint32(offset);
    }
    offset += 4;
    final length = data.getUint32(offset);
    blob = body.sublist(offset + 4, offset + 4 + length);
  } else {
    throw const FormatException('not a key file');
  }
  final digest = pc.SHA256Digest().process(blob);
  return 'SHA256:${base64.encode(digest).replaceAll('=', '')}';
}

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
