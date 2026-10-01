import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// What an OpenSSH user certificate (a -cert.pub file) says, as far as the
/// client shows it. The server checks the rest.
class CertificateInfo {
  const CertificateInfo({
    required this.type,
    required this.blob,
    required this.keyBlob,
    required this.keyId,
    required this.principals,
    required this.validAfter,
    required this.validBefore,
  });

  /// As sent: ssh-ed25519-cert-v01@openssh.com and the like.
  final String type;

  /// The whole certificate, as sent to the server.
  final Uint8List blob;

  /// The public key it certifies, in the key's own wire format.
  final Uint8List keyBlob;

  final String keyId;

  /// The usernames it is valid for; empty means any.
  final List<String> principals;

  /// Null for "always" and "forever".
  final DateTime? validAfter;
  final DateTime? validBefore;

  bool expiredAt(DateTime now) => validBefore != null && now.isAfter(validBefore!);
  bool notYetValidAt(DateTime now) => validAfter != null && now.isBefore(validAfter!);
}

/// Reads a certificate line (`type base64 [comment]`) or its base64;
/// null when it is not a user certificate this client can use.
CertificateInfo? readCertificate(String text) {
  final parts = text.trim().split(RegExp(r'\s+'));
  final encoded = parts.length >= 2 ? parts[1] : parts.first;
  final Uint8List blob;
  try {
    blob = base64.decode(encoded);
  } catch (_) {
    return null;
  }
  try {
    final r = _Reader(blob);
    final type = utf8.decode(r.string());
    if (!type.endsWith('-cert-v01@openssh.com')) return null;
    final keyType = type.substring(0, type.length - '-cert-v01@openssh.com'.length);
    r.string(); // nonce
    // The certified key's fields, between the nonce and the serial.
    final keyStart = r.offset;
    switch (keyType) {
      case 'ssh-ed25519':
        r.string();
      case 'ssh-rsa':
        r
          ..string() // e
          ..string(); // n
      case 'ecdsa-sha2-nistp256' || 'ecdsa-sha2-nistp384' || 'ecdsa-sha2-nistp521':
        r
          ..string() // curve
          ..string(); // point
      default:
        return null;
    }
    final keyFields = Uint8List.sublistView(blob, keyStart, r.offset);
    r.uint64(); // serial
    if (r.uint32() != 1) return null; // 1: a user certificate; 2 is a host one
    final keyId = utf8.decode(r.string(), allowMalformed: true);
    final principals = <String>[];
    final packed = _Reader(r.string());
    while (!packed.done) {
      principals.add(utf8.decode(packed.string(), allowMalformed: true));
    }
    final after = r.uint64();
    final before = r.uint64();
    final name = utf8.encode(keyType);
    final keyBlob =
        (BytesBuilder()
              ..add(_uint32(name.length))
              ..add(name)
              ..add(keyFields))
            .takeBytes();
    return CertificateInfo(
      type: type,
      blob: blob,
      keyBlob: keyBlob,
      keyId: keyId,
      principals: principals,
      validAfter: after == 0 ? null : DateTime.fromMillisecondsSinceEpoch(after * 1000, isUtc: true),
      // 2^64 - 1 is "forever", which an int reads as -1.
      validBefore: before == -1 ? null : DateTime.fromMillisecondsSinceEpoch(before * 1000, isUtc: true),
    );
  } on RangeError {
    return null;
  }
}

/// Whether [certificate] certifies the public key of [privateKey].
bool certificateMatches(CertificateInfo certificate, String privateKey, {String? passphrase}) {
  try {
    final pair = SSHKeyPair.fromPem(privateKey.trim(), (passphrase?.isEmpty ?? true) ? null : passphrase).first;
    final own = pair.toPublicKey().encode();
    if (own.length != certificate.keyBlob.length) return false;
    for (var i = 0; i < own.length; i++) {
      if (own[i] != certificate.keyBlob[i]) return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// The identity that signs in with [certificate] and the key it certifies.
SSHIdentity certificateIdentity(CertificateInfo certificate, SSHKeyPair pair) => SSHIdentity.custom(
  // The certificate's algorithm follows the key's signature: an RSA key
  // signs with rsa-sha2-256, so it is offered as rsa-sha2-256-cert-v01.
  type: '${pair.type}-cert-v01@openssh.com',
  publicKey: SSHRawHostKey(certificate.blob),
  signer: pair.sign,
);

Uint8List _uint32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

class _Reader {
  _Reader(this.bytes);
  final Uint8List bytes;
  var offset = 0;

  bool get done => offset >= bytes.length;

  int uint32() {
    final v = ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);
    offset += 4;
    return v;
  }

  int uint64() {
    final v = ByteData.sublistView(bytes, offset, offset + 8).getInt64(0);
    offset += 8;
    return v;
  }

  Uint8List string() {
    final length = uint32();
    final v = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return v;
  }
}
