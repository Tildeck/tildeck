import 'dart:typed_data';

import '../vault/vault_crypto.dart';

/// The recovery key as the user writes it down (docs/security-model.md,
/// "Recovery key format"): the 32 key bytes and a 2-byte checksum in
/// Crockford Base32, in groups of four characters.
class RecoveryKeyCodec {
  const RecoveryKeyCodec(this.crypto);

  final VaultCrypto crypto;

  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const _keyBytes = 32;
  static const _totalBytes = _keyBytes + 2;

  /// 34 bytes are 272 bits: 55 characters, the last one padded with zeros.
  static const length = (_totalBytes * 8 + 4) ~/ 5;

  String encode(Uint8List key) {
    assert(key.length == _keyBytes);
    final bytes = Uint8List(_totalBytes)
      ..setAll(0, key)
      ..setAll(_keyBytes, crypto.recoveryChecksum(key));
    final out = StringBuffer();
    var buffer = 0, bits = 0, written = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | b;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        _put(out, _alphabet[(buffer >> bits) & 31], written++);
      }
    }
    if (bits > 0) _put(out, _alphabet[(buffer << (5 - bits)) & 31], written++);
    bytes.fillRange(0, bytes.length, 0);
    return out.toString();
  }

  static void _put(StringBuffer out, String char, int index) {
    if (index > 0 && index % 4 == 0) out.write('-');
    out.write(char);
  }

  /// The key bytes, or null when [input] is not a recovery key: a wrong
  /// length, a character outside the alphabet, or a checksum that does not
  /// match, which catches a typing mistake before any network request.
  /// Spaces and dashes are ignored, and letters that Crockford Base32 reads
  /// as digits (O, I, L) are accepted.
  Uint8List? decode(String input) {
    final chars = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (chars.length != length) return null;
    final bytes = Uint8List(_totalBytes);
    var buffer = 0, bits = 0, index = 0;
    for (final rune in chars.runes) {
      final value = _valueOf(String.fromCharCode(rune));
      if (value == null) return null;
      buffer = ((buffer << 5) | value) & 0xfff;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        if (index < _totalBytes) bytes[index++] = (buffer >> bits) & 0xff;
      }
    }
    // The padding bits after the last byte are always zero.
    if (index != _totalBytes || buffer & ((1 << bits) - 1) != 0) return null;
    final key = Uint8List.fromList(bytes.sublist(0, _keyBytes));
    final checksum = crypto.recoveryChecksum(key);
    final ok = checksum[0] == bytes[_keyBytes] && checksum[1] == bytes[_keyBytes + 1];
    bytes.fillRange(0, bytes.length, 0);
    if (!ok) {
      key.fillRange(0, key.length, 0);
      return null;
    }
    return key;
  }

  static int? _valueOf(String c) {
    final normalized = switch (c) {
      'O' => '0',
      'I' || 'L' => '1',
      _ => c,
    };
    final i = _alphabet.indexOf(normalized);
    return i < 0 ? null : i;
  }
}
