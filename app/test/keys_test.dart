import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/keys.dart';
import 'package:tildeck/vault/vault_crypto.dart';

void main() {
  late VaultCrypto crypto;
  setUpAll(() async => crypto = await VaultCrypto.load());

  test('an Ed25519 key reads back with its type, fingerprint, and public key line', () {
    final pem = generateEd25519(crypto.sodium, 'laptop');
    expect(pem, startsWith('-----BEGIN OPENSSH PRIVATE KEY-----'));
    final info = readKey(pem, comment: "Shlomi's laptop")!;
    expect(info.type, 'ssh-ed25519');
    expect(info.fingerprint, matches(RegExp(r'^SHA256:[A-Za-z0-9+/]{43}$')));
    expect(info.publicKey, startsWith('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5'));
    expect(info.publicKey, endsWith(' Shlomi-s-laptop'), reason: 'the comment needs no quoting');
    expect(generateEd25519(crypto.sodium, 'x'), isNot(pem), reason: 'every key is new');
  });

  test('an RSA key', () async {
    final pem = await generateRsa(1024, 'old-server');
    final info = readKey(pem)!;
    expect(info.type, 'ssh-rsa');
    expect(info.publicKey, startsWith('ssh-rsa AAAAB3NzaC1yc2E'));
  });

  test('an exported key with a passphrase opens only with it, and is the same key', () {
    final pem = generateEd25519(crypto.sodium, 'k');
    final fingerprint = readKey(pem)!.fingerprint;
    final protected = exportKey(pem, newPassphrase: 'orange-kettle');
    expect(protected, isNot(pem));
    expect(readKey(protected), isNull);
    expect(readKey(protected, passphrase: 'wrong'), isNull);
    expect(readKey(protected, passphrase: 'orange-kettle')!.fingerprint, fingerprint);
    // Exported without one, a protected key comes out open.
    expect(readKey(exportKey(protected, passphrase: 'orange-kettle'))!.fingerprint, fingerprint);
  });

  test('what is not a key is not read', () {
    expect(readKey(''), isNull);
    expect(readKey('ssh-ed25519 AAAA public only'), isNull);
  });

  test('installing refuses a line that could break out of the quotes', () {
    expect(() => installKeyCommand("ssh-ed25519 AAAA x'; rm -rf ~; '"), throwsArgumentError);
    expect(installKeyCommand('ssh-ed25519 AAAA me'), contains("grep -qxF 'ssh-ed25519 AAAA me'"));
  });
}
