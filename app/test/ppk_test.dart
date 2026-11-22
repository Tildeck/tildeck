// PuTTY key files made by puttygen 0.83 for each test run (generated_keys.dart,
// scripts/verify.sh), checked against puttygen's own fingerprint of each.
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/keys.dart';
import 'package:tildeck/ssh/ppk.dart';

import 'generated_keys.dart';

/// What each generated file must be, so a generator that wrote another
/// format, cipher, or key derivation fails here instead of testing the
/// wrong case.
const files = {
  'ed25519-v3-plain': (version: 3, type: 'ssh-ed25519', kdf: null, encrypted: false),
  'ed25519-v3-argon2id': (version: 3, type: 'ssh-ed25519', kdf: 'Argon2id', encrypted: true),
  'ecdsa256-v3-plain': (version: 3, type: 'ecdsa-sha2-nistp256', kdf: null, encrypted: false),
  'ecdsa384-v3-argon2d': (version: 3, type: 'ecdsa-sha2-nistp384', kdf: 'Argon2d', encrypted: true),
  'rsa-v3-argon2i': (version: 3, type: 'ssh-rsa', kdf: 'Argon2i', encrypted: true),
  'rsa-v2-encrypted': (version: 2, type: 'ssh-rsa', kdf: null, encrypted: true),
  'ed25519-v2-plain': (version: 2, type: 'ssh-ed25519', kdf: null, encrypted: false),
  'ecdsa521-v2-plain': (version: 2, type: 'ecdsa-sha2-nistp521', kdf: null, encrypted: false),
  'dsa-v3-plain': (version: 3, type: 'ssh-dss', kdf: null, encrypted: false),
};

/// The header fields of a PuTTY key file. Key data lines have no ": ".
Map<String, String> headerOf(String ppk) => {
  for (final line in ppk.split('\n'))
    if (line.contains(': ')) line.substring(0, line.indexOf(': ')): line.substring(line.indexOf(': ') + 2).trim(),
};

/// Why a conversion failed, or null when it gave a key. The key itself is
/// never handed to a matcher, so a failing test cannot print it.
PpkProblem? problemOf(String ppk, {String? passphrase}) {
  try {
    ppkToOpenSsh(ppk, passphrase: passphrase);
    return null;
  } on PpkException catch (e) {
    return e.problem;
  }
}

void main() {
  group('generated files', skip: keyFilesSkip, () {
    for (final MapEntry(key: name, value: expected) in files.entries) {
      test('$name is the format it is named for', () {
        final header = headerOf(keyFile('$name.ppk'));
        expect(header['PuTTY-User-Key-File-${expected.version}'], expected.type, reason: 'format and key type');
        expect(header['Encryption'], expected.encrypted ? 'aes256-cbc' : 'none');
        expect(header['Key-Derivation'], expected.kdf);
        if (expected.kdf != null) {
          expect((header['Argon2-Memory'], header['Argon2-Passes'], header['Argon2-Parallelism']), ('8192', '21', '1'));
        }
        expect(keyFileFingerprint(name).type, expected.type);
      });
    }

    for (final MapEntry(key: name, value: expected) in files.entries) {
      if (expected.type == 'ssh-dss') continue;
      test('$name becomes the same key in OpenSSH form, and it signs', () {
        final ppk = keyFile('$name.ppk');
        expect(looksLikePpk(ppk), isTrue);
        expect(ppkIsEncrypted(ppk), expected.encrypted);
        final pem = ppkToOpenSsh(ppk, passphrase: expected.encrypted ? keyFilePassphrase : null);
        expect(pem.startsWith('-----BEGIN OPENSSH PRIVATE KEY-----'), isTrue, reason: 'OpenSSH form');

        // The same public key as puttygen reports.
        final puttygen = keyFileFingerprint(name);
        final info = readKey(pem, comment: name)!;
        expect(info.type, puttygen.type);
        expect(info.fingerprint, puttygen.fingerprint);

        // And the private half belongs to it: a signature verifies.
        final pair = SSHKeyPair.fromPem(pem).single;
        final message = Uint8List.fromList('tildeck'.codeUnits);
        final signature = pair.sign(message);
        expect((pair.toPublicKey() as dynamic).verify(message, signature), isTrue);
      });
    }

    test('an encrypted key asks for its passphrase, and refuses a wrong one', () {
      final ppk = keyFile('ed25519-v3-argon2id.ppk');
      expect(problemOf(ppk), PpkProblem.passphraseNeeded);
      expect(problemOf(ppk, passphrase: ''), PpkProblem.passphraseNeeded);
      expect(problemOf(ppk, passphrase: 'not-it'), PpkProblem.wrongPassphrase);
      expect(problemOf(keyFile('rsa-v2-encrypted.ppk'), passphrase: 'not-it'), PpkProblem.wrongPassphrase);
    });

    test('a changed file is caught by its MAC', () {
      final lines = keyFile('ed25519-v3-plain.ppk').split('\n');
      final comment = lines.indexWhere((l) => l.startsWith('Comment: '));
      lines[comment] = 'Comment: someone-else';
      expect(problemOf(lines.join('\n')), PpkProblem.malformed);
    });

    test('a key type Tildeck does not use is named as such, and an edited one fails its MAC', () {
      expect(problemOf(keyFile('dsa-v3-plain.ppk')), PpkProblem.unsupported);
      final relabelled = keyFile('ed25519-v3-plain.ppk').replaceFirst('ssh-ed25519', 'ssh-dss');
      expect(problemOf(relabelled), PpkProblem.malformed, reason: 'the MAC covers the algorithm name');
    });
  });

  test('other text is not a PuTTY key', () {
    expect(looksLikePpk('-----BEGIN OPENSSH PRIVATE KEY-----'), isFalse);
    expect(problemOf('PuTTY-User-Key-File-3: ssh-ed25519\nEncryption: none\n'), PpkProblem.malformed);
  });
}
