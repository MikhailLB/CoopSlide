import 'dart:typed_data';

/// XOR deobfuscation keyed by a project-specific seed phrase.
/// Change [ _seed ] when forking to another app.
Uint8List _buildKey() {
  const seed = <int>[99, 111, 111, 112, 115, 108, 100, 55]; // "coopsld7"
  var state = seed.fold<int>(0, (a, b) => (a * 31 + b) & 0xFFFFFFFF);
  final key = Uint8List(16);
  for (var i = 0; i < key.length; i++) {
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
    key[i] = state & 0xFF;
  }
  return key;
}

final _mask = _buildKey();

String reveal(List<int> blob) {
  final out = Uint8List(blob.length);
  for (var i = 0; i < blob.length; i++) {
    out[i] = blob[i] ^ _mask[i % _mask.length];
  }
  return String.fromCharCodes(out);
}
