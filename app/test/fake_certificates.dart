// Builds OpenSSH user certificates for tests, field by field.
import 'dart:convert';
import 'dart:typed_data';

/// An OpenSSH user certificate for [publicKeyLine]'s Ed25519 key, built field
/// by field (the signature is not checked here; the server checks it).
String certificateFor(
  String publicKeyLine, {
  List<String> principals = const ['deploy'],
  int before = -1,
  int kind = 1,
}) {
  final keyBlob = base64.decode(publicKeyLine.split(' ')[1]);
  // The key blob is string("ssh-ed25519") + string(pk): keep the pk part.
  final pk = Uint8List.sublistView(keyBlob, 4 + 11);
  final out = BytesBuilder();
  void u32(int v) => out.add(Uint8List(4)..buffer.asByteData().setUint32(0, v));
  void u64(int v) => out.add(Uint8List(8)..buffer.asByteData().setInt64(0, v));
  void str(List<int> b) {
    u32(b.length);
    out.add(b);
  }

  str(utf8.encode('ssh-ed25519-cert-v01@openssh.com'));
  str(List.filled(32, 7)); // nonce
  out.add(pk);
  u64(42); // serial
  u32(kind);
  str(utf8.encode('key-id'));
  final packed = BytesBuilder();
  for (final p in principals) {
    final b = utf8.encode(p);
    packed.add(Uint8List(4)..buffer.asByteData().setUint32(0, b.length));
    packed.add(b);
  }
  str(packed.takeBytes());
  u64(0);
  u64(before);
  str(const []); // critical options
  str(const []); // extensions
  str(const []); // reserved
  str(utf8.encode('signature key'));
  str(utf8.encode('signature'));
  return 'ssh-ed25519-cert-v01@openssh.com ${base64.encode(out.takeBytes())} me@laptop';
}
