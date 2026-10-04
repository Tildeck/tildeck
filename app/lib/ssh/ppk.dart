import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

/// Why a PuTTY key file could not be read.
enum PpkProblem {
  /// Not a PuTTY key file, or a damaged one.
  malformed,

  /// Encrypted, and no passphrase was given.
  passphraseNeeded,

  /// Encrypted, and the passphrase does not open it.
  wrongPassphrase,

  /// A key type Tildeck does not use (DSA, Ed448).
  unsupported,
}

class PpkException implements Exception {
  const PpkException(this.problem);
  final PpkProblem problem;

  @override
  String toString() => 'PpkException($problem)';
}

/// Whether [text] is a PuTTY private key file (.ppk).
bool looksLikePpk(String text) => text.trimLeft().startsWith('PuTTY-User-Key-File-');

/// Whether the PuTTY key in [text] is encrypted with a passphrase.
bool ppkIsEncrypted(String text) => _Ppk.parse(text).encryption != 'none';

/// The PuTTY private key in [text] (format 2 or 3, as PuTTYgen writes them)
/// as an OpenSSH private key, unencrypted: it is kept only inside the
/// vault, which is encrypted. Throws [PpkException].
///
/// Format: https://tartarus.org/~simon/putty-snapshots/htmldoc/AppendixC.html
String ppkToOpenSsh(String text, {String? passphrase}) {
  final ppk = _Ppk.parse(text);
  final encrypted = ppk.encryption != 'none';
  if (ppk.encryption != 'none' && ppk.encryption != 'aes256-cbc') {
    throw const PpkException(PpkProblem.unsupported);
  }
  if (encrypted && (passphrase == null || passphrase.isEmpty)) {
    throw const PpkException(PpkProblem.passphraseNeeded);
  }
  final pass = utf8.encode(encrypted ? passphrase! : '');

  // The cipher key, its IV, and the MAC key, by format.
  final Uint8List cipherKey;
  final Uint8List iv;
  final Uint8List macKey;
  final pc.Digest macDigest;
  if (ppk.version == 2) {
    cipherKey = Uint8List.fromList([
      ...pc.SHA1Digest().process(Uint8List.fromList([0, 0, 0, 0, ...pass])),
      ...pc.SHA1Digest().process(Uint8List.fromList([0, 0, 0, 1, ...pass])),
    ]).sublist(0, 32);
    iv = Uint8List(16);
    macKey = pc.SHA1Digest().process(Uint8List.fromList([...ascii.encode('putty-private-key-file-mac-key'), ...pass]));
    macDigest = pc.SHA1Digest();
  } else {
    if (encrypted) {
      final derived = ppk.argon2(Uint8List.fromList(pass));
      cipherKey = derived.sublist(0, 32);
      iv = derived.sublist(32, 48);
      macKey = derived.sublist(48, 80);
    } else {
      cipherKey = Uint8List(0);
      iv = Uint8List(0);
      macKey = Uint8List(0);
    }
    macDigest = pc.SHA256Digest();
  }

  final private = encrypted ? _aesCbcDecrypt(ppk.privateBlob, cipherKey, iv) : ppk.privateBlob;
  // SHA-1 and SHA-256 both work on 64-byte blocks.
  final mac = pc.HMac(macDigest, 64)..init(pc.KeyParameter(macKey));
  final signed = _SshWriter()
    ..string(ascii.encode(ppk.algorithm))
    ..string(ascii.encode(ppk.encryption))
    ..string(utf8.encode(ppk.comment))
    ..string(ppk.publicBlob)
    ..string(private);
  final expected = mac.process(signed.bytes);
  if (!_equal(expected, ppk.mac)) {
    throw PpkException(encrypted ? PpkProblem.wrongPassphrase : PpkProblem.malformed);
  }
  return _openSshPem(ppk.algorithm, ppk.publicBlob, private, ppk.comment);
}

/// The parts of a .ppk file.
class _Ppk {
  _Ppk({
    required this.version,
    required this.algorithm,
    required this.encryption,
    required this.comment,
    required this.publicBlob,
    required this.privateBlob,
    required this.mac,
    required this.headers,
  });

  final int version;
  final String algorithm;
  final String encryption;
  final String comment;
  final Uint8List publicBlob;
  final Uint8List privateBlob;
  final Uint8List mac;
  final Map<String, String> headers;

  static _Ppk parse(String text) {
    final lines = const LineSplitter().convert(text.trim());
    if (lines.isEmpty) throw const PpkException(PpkProblem.malformed);
    final first = RegExp(r'^PuTTY-User-Key-File-([23]): (\S+)$').firstMatch(lines.first.trim());
    if (first == null) throw const PpkException(PpkProblem.malformed);
    final headers = <String, String>{};
    final blobs = <String, Uint8List>{};
    var i = 1;
    try {
      while (i < lines.length) {
        final line = lines[i++];
        final colon = line.indexOf(': ');
        if (colon < 0) throw const PpkException(PpkProblem.malformed);
        final name = line.substring(0, colon);
        final value = line.substring(colon + 2).trim();
        if (name == 'Public-Lines' || name == 'Private-Lines') {
          final count = int.parse(value);
          if (count < 0 || i + count > lines.length) throw const PpkException(PpkProblem.malformed);
          blobs[name] = base64.decode(lines.sublist(i, i + count).map((l) => l.trim()).join());
          i += count;
        } else {
          headers[name] = value;
        }
      }
      final public = blobs['Public-Lines'];
      final private = blobs['Private-Lines'];
      final mac = headers['Private-MAC'];
      if (public == null || private == null || mac == null) throw const PpkException(PpkProblem.malformed);
      return _Ppk(
        version: int.parse(first[1]!),
        algorithm: first[2]!,
        encryption: headers['Encryption'] ?? 'none',
        comment: headers['Comment'] ?? '',
        publicBlob: public,
        privateBlob: private,
        mac: _hex(mac),
        headers: headers,
      );
    } on PpkException {
      rethrow;
    } catch (_) {
      throw const PpkException(PpkProblem.malformed);
    }
  }

  /// Format 3: 80 bytes from the passphrase with the file's Argon2
  /// parameters: the cipher key, its IV, and the MAC key.
  Uint8List argon2(Uint8List passphrase) {
    final type = switch (headers['Key-Derivation']) {
      'Argon2id' => pc.Argon2Parameters.ARGON2_id,
      'Argon2i' => pc.Argon2Parameters.ARGON2_i,
      'Argon2d' => pc.Argon2Parameters.ARGON2_d,
      _ => throw const PpkException(PpkProblem.unsupported),
    };
    final int memory;
    final int passes;
    final int lanes;
    final Uint8List salt;
    try {
      memory = int.parse(headers['Argon2-Memory']!);
      passes = int.parse(headers['Argon2-Passes']!);
      lanes = int.parse(headers['Argon2-Parallelism']!);
      salt = _hex(headers['Argon2-Salt']!);
    } catch (_) {
      throw const PpkException(PpkProblem.malformed);
    }
    // A file asking for more than PuTTY ever writes is refused, not run.
    if (memory < 8 || memory > 1 << 20 || passes < 1 || passes > 1000 || lanes < 1 || lanes > 16) {
      throw const PpkException(PpkProblem.unsupported);
    }
    final generator = pc.Argon2BytesGenerator()
      ..init(
        pc.Argon2Parameters(
          type,
          salt,
          desiredKeyLength: 80,
          iterations: passes,
          memory: memory,
          lanes: lanes,
          version: pc.Argon2Parameters.ARGON2_VERSION_13,
        ),
      );
    return generator.process(passphrase);
  }
}

Uint8List _aesCbcDecrypt(Uint8List data, Uint8List key, Uint8List iv) {
  if (data.length % 16 != 0) throw const PpkException(PpkProblem.malformed);
  final cipher = pc.CBCBlockCipher(pc.AESEngine())..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
  final out = Uint8List(data.length);
  for (var offset = 0; offset < data.length; offset += 16) {
    cipher.processBlock(data, offset, out, offset);
  }
  return out;
}

/// An OpenSSH private key file ("openssh-key-v1", unencrypted) holding the
/// key that PuTTY's public and private blobs describe.
String _openSshPem(String algorithm, Uint8List publicBlob, Uint8List privateBlob, String comment) {
  final public = _SshReader(publicBlob);
  final type = ascii.decode(public.string());
  if (type != algorithm) throw const PpkException(PpkProblem.malformed);
  final private = _SshReader(privateBlob);
  final key = _SshWriter()..string(ascii.encode(type));
  switch (type) {
    case 'ssh-ed25519':
      final pub = public.string();
      final seed = private.string();
      if (pub.length != 32 || seed.length != 32) throw const PpkException(PpkProblem.malformed);
      key
        ..string(pub)
        ..string(Uint8List.fromList([...seed, ...pub]));
    case 'ssh-rsa':
      final e = public.raw();
      final n = public.raw();
      final d = private.raw();
      final p = private.raw();
      final q = private.raw();
      final iqmp = private.raw();
      key
        ..add(n)
        ..add(e)
        ..add(d)
        ..add(iqmp)
        ..add(p)
        ..add(q);
    case 'ecdsa-sha2-nistp256' || 'ecdsa-sha2-nistp384' || 'ecdsa-sha2-nistp521':
      final curve = public.raw();
      final point = public.raw();
      final d = private.raw();
      key
        ..add(curve)
        ..add(point)
        ..add(d);
    default:
      throw const PpkException(PpkProblem.unsupported);
  }
  key.string(utf8.encode(comment));

  final check = Random.secure().nextInt(1 << 32);
  final section = _SshWriter()
    ..uint32(check)
    ..uint32(check)
    ..add(key.bytes);
  for (var pad = 1; section.length % 8 != 0; pad++) {
    section.add(Uint8List.fromList([pad]));
  }
  final file = _SshWriter()
    ..add(Uint8List.fromList([...ascii.encode('openssh-key-v1'), 0]))
    ..string(ascii.encode('none'))
    ..string(ascii.encode('none'))
    ..string(Uint8List(0))
    ..uint32(1)
    ..string(publicBlob)
    ..string(section.bytes);
  final body = base64.encode(file.bytes);
  final wrapped = [for (var i = 0; i < body.length; i += 70) body.substring(i, min(i + 70, body.length))];
  return '-----BEGIN OPENSSH PRIVATE KEY-----\n${wrapped.join('\n')}\n-----END OPENSSH PRIVATE KEY-----\n';
}

Uint8List _hex(String hex) {
  if (hex.length.isOdd) throw const PpkException(PpkProblem.malformed);
  return Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Reads SSH wire-format fields (RFC 4251, 5).
class _SshReader {
  _SshReader(this._data);
  final Uint8List _data;
  var _at = 0;

  int _length() {
    if (_at + 4 > _data.length) throw const PpkException(PpkProblem.malformed);
    final n = ByteData.sublistView(_data, _at, _at + 4).getUint32(0);
    if (_at + 4 + n > _data.length) throw const PpkException(PpkProblem.malformed);
    return n;
  }

  /// A string's contents.
  Uint8List string() {
    final n = _length();
    final value = Uint8List.sublistView(_data, _at + 4, _at + 4 + n);
    _at += 4 + n;
    return value;
  }

  /// A string or mpint as it is on the wire, length included.
  Uint8List raw() {
    final n = _length();
    final value = Uint8List.sublistView(_data, _at, _at + 4 + n);
    _at += 4 + n;
    return value;
  }
}

class _SshWriter {
  final _out = BytesBuilder();

  int get length => _out.length;
  Uint8List get bytes => _out.toBytes();

  void uint32(int v) => _out.add((ByteData(4)..setUint32(0, v)).buffer.asUint8List());
  void add(Uint8List v) => _out.add(v);
  void string(List<int> v) {
    uint32(v.length);
    _out.add(v);
  }
}
