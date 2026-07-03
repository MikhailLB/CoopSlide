import 'dart:typed_data';

Uint8List _deriveKey(List<int> parts) {
  if (parts.isEmpty) return Uint8List(16);
  var seed = parts.fold<int>(0, (a, b) => (a * 31 + b) & 0xFFFFFFFF);
  final key = Uint8List(16);
  var v = seed;
  for (var i = 0; i < key.length; i++) {
    v = (v * 1103515245 + 12345) & 0x7FFFFFFF;
    key[i] = v & 0xFF;
  }
  return key;
}

List<int> encode(String plain, List<int> seedParts) {
  final key = _deriveKey(seedParts);
  return plain.codeUnits
      .asMap()
      .entries
      .map((e) => e.value ^ key[e.key % key.length])
      .toList();
}

void main() {
  const seed = [99, 111, 111, 112, 115, 108, 100, 55]; // coopsld7
  const items = [
    'https://coopslide.com',
    '/config.php',
    '132.0.6834.163',
    '537.36',
    'https://gcdsdk.appsflyer.com/install_data/v4.0/',
    'qb5JfLNGoAsZmYs5q8ZuCH',
    '363611599409',
  ];
  for (final s in items) {
    final bytes = encode(s, seed);
    print('// "$s"');
    print('const _ = <int>[${bytes.join(', ')}];');
    print('');
  }
}
