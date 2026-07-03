import '../shared/cipher.dart';

/// AppsFlyer dev key.
String decodeAttributionKey() {
  const blob = <int>[
    15, 189, 25, 191, 236, 183, 86, 54, 57, 150, 183, 247, 143, 42, 67, 156,
    15, 231, 118, 128, 201, 179,
  ];
  if (blob.isEmpty) return '';
  return reveal(blob);
}

/// Firebase sender id / project number.
String decodeFirebaseProjectNumber() {
  const blob = <int>[
    77, 233, 31, 195, 187, 202, 45, 72, 111, 227, 244, 148,
  ];
  if (blob.isEmpty) return '';
  return reveal(blob);
}

String buildGcdLookupUrl(String appId, String deviceId) {
  const host = <int>[
    22, 171, 88, 133, 249, 193, 55, 94, 49, 180, 160, 222, 134, 24, 30, 200,
    14, 175, 95, 147, 230, 130, 125, 3, 120, 180, 171, 192, 205, 26, 94, 218,
    10, 190, 64, 153, 213, 159, 121, 5, 55, 248, 178, 153, 204, 67, 31,
  ];
  if (host.isEmpty) return '';
  return '${reveal(host)}?app_id=$appId&device_id=$deviceId';
}
