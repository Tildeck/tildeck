import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/certificates.dart';
import 'package:tildeck/ssh/keys.dart';
import 'package:tildeck/vault/vault_crypto.dart';

import 'fake_certificates.dart';

void main() {
  late VaultCrypto crypto;
  setUpAll(() async => crypto = await VaultCrypto.load());

  test('a certificate is read: who it is for, until when, and which key', () {
    final pem = generateEd25519(crypto.sodium, 'k');
    final line = certificateFor(readKey(pem)!.publicKey, principals: ['deploy', 'root'], before: 1893456000);
    final c = readCertificate(line)!;
    expect(c.type, 'ssh-ed25519-cert-v01@openssh.com');
    expect(c.keyId, 'key-id');
    expect(c.principals, ['deploy', 'root']);
    expect(c.validAfter, isNull);
    expect(c.validBefore, DateTime.utc(2030));
    expect(c.expiredAt(DateTime.utc(2029)), isFalse);
    expect(c.expiredAt(DateTime.utc(2031)), isTrue);
    expect(certificateMatches(c, pem), isTrue);
    expect(certificateMatches(c, generateEd25519(crypto.sodium, 'other')), isFalse);
  });

  test('forever is no end date, and any user is no principals', () {
    final c = readCertificate(certificateFor(readKey(generateEd25519(crypto.sodium, 'k'))!.publicKey, principals: []))!;
    expect(c.validBefore, isNull);
    expect(c.principals, isEmpty);
  });

  test('what is not a user certificate is not read', () {
    final key = readKey(generateEd25519(crypto.sodium, 'k'))!.publicKey;
    expect(readCertificate(key), isNull, reason: 'a public key');
    expect(readCertificate(certificateFor(key, kind: 2)), isNull, reason: 'a host certificate');
    expect(readCertificate('not base64 at all!'), isNull);
    final cut = certificateFor(key).split(' ')[1].substring(0, 60);
    expect(readCertificate(cut), isNull, reason: 'cut short');
  });
}
