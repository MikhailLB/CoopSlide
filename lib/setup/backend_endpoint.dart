import '../shared/cipher.dart';

String decodeConfigEndpoint() {
  const host = <int>[
    22, 171, 88, 133, 249, 193, 55, 94, 53, 184, 171, 221, 145, 31, 89, 205,
    27, 241, 79, 154, 231,
  ];
  const path = <int>[81, 188, 67, 155, 236, 146, 127, 95, 38, 191, 180];
  return reveal(host) + reveal(path);
}
