import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../shared/cipher.dart';

String _chromeBuild() => reveal(const <int>[
      79, 236, 30, 219, 186, 213, 46, 73, 101, 227, 234, 156, 212, 64,
    ]);

String _webkitBuild() => reveal(const <int>[75, 236, 27, 219, 185, 205]);

class OutboundHttp extends http.BaseClient {
  final http.Client _delegate = http.Client();
  String? _agent;

  Future<void> bootstrap() async {
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        // `version.release` is the user-visible Android version string
        // (e.g. "16"). `version.sdkInt` is the API level (e.g. 36 for
        // Android 16) and is NOT what the UA "Android <n>" segment should
        // contain, so we fall back to the SDK int only if release is empty.
        final androidVersion = info.version.release.isNotEmpty
            ? info.version.release
            : info.version.sdkInt.toString();
        final model = info.model;
        final brand = info.brand;
        final build =
            info.display.isNotEmpty ? info.display : info.id;
        final chrome = _chromeBuild();
        _agent =
            'Mozilla/5.0 (Linux; Android $androidVersion; $brand $model Build/$build) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$chrome '
            'Mobile Safari/537.36';
      } else {
        final ios = await DeviceInfoPlugin().iosInfo;
        final ver = ios.systemVersion.replaceAll('.', '_');
        final webkit = _webkitBuild();
        _agent =
            'Mozilla/5.0 (iPhone; CPU iPhone OS $ver like Mac OS X) '
            'AppleWebKit/$webkit (KHTML, like Gecko) '
            'Version/${ios.systemVersion} Mobile/15E148 Safari/$webkit';
      }
    } catch (_) {
      final chrome = _chromeBuild();
      _agent =
          'Mozilla/5.0 (Linux; Android 15; SM-S931U Build/AP3A.240905.015.A2) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$chrome '
          'Mobile Safari/537.36';
    }
  }

  String get agent => _agent ?? 'Mozilla/5.0';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => agent);
    return _delegate.send(request);
  }

  @override
  void close() => _delegate.close();
}

final outboundHttp = OutboundHttp();
