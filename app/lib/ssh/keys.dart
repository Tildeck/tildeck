import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pointycastle/export.dart' as pc;
import 'package:sodium/sodium_sumo.dart';

enum KeyKind { ed25519, rsa4096 }

/// A new Ed25519 key in OpenSSH format. The vault encrypts it at rest, so it
/// has no passphrase of its own.
String generateEd25519(SodiumSumo sodium, String comment) {
  final pair = sodium.crypto.sign.keyPair();
  try {
    // libsodium's secret key is OpenSSH's: the seed followed by the public key.
    return OpenSSHEd25519KeyPair(pair.publicKey, pair.secretKey.extractBytes(), comment).toPem();
  } finally {
    pair.secretKey.dispose();
  }
}

/// A new 4096-bit RSA key in OpenSSH format, for servers too old for
/// Ed25519. Generating one takes seconds, so it runs off the UI thread.
Future<String> generateRsa4096(String comment) => generateRsa(4096, comment);

/// A new RSA key of [bits]; tests use a smaller one to stay fast.
@visibleForTesting
Future<String> generateRsa(int bits, String comment) => Isolate.run(() => _rsa(bits, comment));

String _rsa(int bits, String comment) {
  final seed = Random.secure();
  final random = pc.FortunaRandom()
    ..seed(pc.KeyParameter(Uint8List.fromList(List.generate(32, (_) => seed.nextInt(256)))));
  final generator = pc.RSAKeyGenerator()
    ..init(pc.ParametersWithRandom(pc.RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64), random));
  final pair = generator.generateKeyPair();
  final private = pair.privateKey;
  final p = private.p!;
  final q = private.q!;
  return OpenSSHRsaKeyPair(
    private.modulus!,
    private.publicExponent!,
    private.privateExponent!,
    q.modInverse(p),
    p,
    q,
    comment,
  ).toPem();
}

/// What a private key shows: its type, fingerprint, and public key line.
class KeyInfo {
  const KeyInfo({required this.type, required this.fingerprint, required this.publicKey});

  /// As OpenSSH names it: ssh-ed25519, ssh-rsa, ecdsa-sha2-nistp256.
  final String type;

  /// SHA256:..., as ssh-keygen -l shows it.
  final String fingerprint;

  /// One line for authorized_keys: type, key, and comment.
  final String publicKey;
}

/// Reads [pem]; null when it is not a key, or its passphrase is missing or
/// wrong.
KeyInfo? readKey(String pem, {String? passphrase, String comment = ''}) {
  final List<SSHKeyPair> pairs;
  try {
    pairs = SSHKeyPair.fromPem(pem.trim(), (passphrase?.isEmpty ?? true) ? null : passphrase);
  } catch (_) {
    return null;
  }
  if (pairs.isEmpty) return null;
  final blob = pairs.first.toPublicKey().encode();
  // The blob starts with the type name, its length first (RFC 4253, 6.6).
  final length = ByteData.sublistView(blob, 0, 4).getUint32(0);
  final type = ascii.decode(Uint8List.sublistView(blob, 4, 4 + length));
  final digest = pc.SHA256Digest().process(blob);
  final fingerprint = 'SHA256:${base64.encode(digest).replaceAll('=', '')}';
  // A comment goes into a shell command when the key is installed: keep it
  // to characters that need no quoting.
  final safeComment = comment.replaceAll(RegExp(r'[^A-Za-z0-9@._+-]'), '-');
  final line = '$type ${base64.encode(blob)}${safeComment.isEmpty ? '' : ' $safeComment'}';
  return KeyInfo(type: type, fingerprint: fingerprint, publicKey: line);
}

/// [pem] again, encrypted with [passphrase] in OpenSSH's own format, for a
/// file that leaves the vault; or as is when there is no passphrase.
String exportKey(String pem, {String? passphrase, String? newPassphrase}) {
  final pair = SSHKeyPair.fromPem(pem.trim(), (passphrase?.isEmpty ?? true) ? null : passphrase).first;
  final next = (newPassphrase?.isEmpty ?? true) ? null : newPassphrase;
  if (pair is OpenSSHKeyPair) return pair.toPem(passphrase: next);
  if (next == null) return pair.toPem();
  throw UnsupportedError('Only OpenSSH keys can be exported with a passphrase.');
}

/// The command that adds [publicKey] to the account's authorized_keys on a
/// server, once, creating the file with the modes sshd insists on.
String installKeyCommand(String publicKey) {
  if (publicKey.contains("'") || publicKey.contains('\n')) {
    throw ArgumentError('A public key line has no quotes or line breaks.');
  }
  return "umask 077; mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && "
      "(grep -qxF '$publicKey' ~/.ssh/authorized_keys || echo '$publicKey' >> ~/.ssh/authorized_keys) && "
      "echo tildeck-key-installed";
}
