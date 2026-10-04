// PuTTY key files made by puttygen 0.83 (putty-tools) for these tests; the
// .fp beside each is puttygen's own SHA256 fingerprint of it. The encrypted
// ones use the passphrase "tildeck-test".
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/keys.dart';
import 'package:tildeck/ssh/ppk.dart';

const passphrase = 'tildeck-test';

String fixture(String name) => File('test/fixtures/ppk/$name').readAsStringSync();

void main() {
  const files = {
    'ed25519-v3-plain': false,
    'ed25519-v3-argon2id': true,
    'ecdsa256-v3-plain': false,
    'ecdsa384-v3-argon2d': true,
    'rsa-v3-argon2i': true,
    'rsa-v2-encrypted': true,
    'ed25519-v2-plain': false,
    'ecdsa521-v2-plain': false,
  };

  for (final MapEntry(key: name, value: encrypted) in files.entries) {
    test('$name becomes the same key in OpenSSH form, and it signs', () {
      final ppk = fixture('$name.ppk');
      expect(looksLikePpk(ppk), isTrue);
      expect(ppkIsEncrypted(ppk), encrypted);
      final pem = ppkToOpenSsh(ppk, passphrase: encrypted ? passphrase : null);
      expect(pem, startsWith('-----BEGIN OPENSSH PRIVATE KEY-----'));

      // The same public key as puttygen reports.
      final parts = fixture('$name.fp').trim().split(' ');
      final info = readKey(pem, comment: name)!;
      expect(info.type, parts.first);
      expect(info.fingerprint, parts.last);

      // And the private half belongs to it: a signature verifies.
      final pair = SSHKeyPair.fromPem(pem).single;
      final message = Uint8List.fromList('tildeck'.codeUnits);
      final signature = pair.sign(message);
      expect((pair.toPublicKey() as dynamic).verify(message, signature), isTrue);
    });
  }

  test('an encrypted key asks for its passphrase, and refuses a wrong one', () {
    final ppk = fixture('ed25519-v3-argon2id.ppk');
    PpkProblem problem(String? pass) {
      try {
        ppkToOpenSsh(ppk, passphrase: pass);
        return PpkProblem.malformed;
      } on PpkException catch (e) {
        return e.problem;
      }
    }

    expect(problem(null), PpkProblem.passphraseNeeded);
    expect(problem(''), PpkProblem.passphraseNeeded);
    expect(problem('not-it'), PpkProblem.wrongPassphrase);
    expect(
      () => ppkToOpenSsh(fixture('rsa-v2-encrypted.ppk'), passphrase: 'not-it'),
      throwsA(isA<PpkException>().having((e) => e.problem, 'problem', PpkProblem.wrongPassphrase)),
    );
  });

  test('a changed file is caught by its MAC, and other text is not a PuTTY key', () {
    final lines = fixture('ed25519-v3-plain.ppk').split('\n');
    final comment = lines.indexWhere((l) => l.startsWith('Comment: '));
    lines[comment] = 'Comment: someone-else';
    expect(
      () => ppkToOpenSsh(lines.join('\n')),
      throwsA(isA<PpkException>().having((e) => e.problem, 'problem', PpkProblem.malformed)),
    );
    expect(looksLikePpk('-----BEGIN OPENSSH PRIVATE KEY-----'), isFalse);
    expect(
      () => ppkToOpenSsh('PuTTY-User-Key-File-3: ssh-ed25519\nEncryption: none\n'),
      throwsA(isA<PpkException>().having((e) => e.problem, 'problem', PpkProblem.malformed)),
    );
  });

  test('a key type Tildeck does not use is named as such, and an edited one fails its MAC', () {
    expect(
      () => ppkToOpenSsh(fixture('dsa-v3-plain.ppk')),
      throwsA(isA<PpkException>().having((e) => e.problem, 'problem', PpkProblem.unsupported)),
    );
    final relabelled = fixture('ed25519-v3-plain.ppk').replaceFirst('ssh-ed25519', 'ssh-dss');
    expect(
      () => ppkToOpenSsh(relabelled),
      throwsA(isA<PpkException>().having((e) => e.problem, 'problem', PpkProblem.malformed)),
      reason: 'the MAC covers the algorithm name',
    );
  });
}
