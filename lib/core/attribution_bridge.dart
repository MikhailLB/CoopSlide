import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../setup/attribution_keys.dart';
import '../setup/project_constants.dart';
import 'outbound_http.dart';

class AttributionBridge {
  AppsflyerSdk? _sdk;
  Map<String, dynamic>? _installPayload;
  Map<String, dynamic>? _deepLinkPayload;
  Map<String, dynamic>? _openPayload;
  final _installGate = Completer<Map<String, dynamic>>();
  final _deepLinkGate = Completer<void>();
  bool _bootstrapped = false;

  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    final devKey = ProjectConstants.attributionDevKey;
    if (devKey.isEmpty) {
      if (!_installGate.isCompleted) {
        _installGate.complete(<String, dynamic>{});
      }
      if (!_deepLinkGate.isCompleted) _deepLinkGate.complete();
      return;
    }

    final options = AppsFlyerOptions(
      afDevKey: devKey,
      appId: ProjectConstants.attributionAppId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );
    _sdk = AppsflyerSdk(options);

    _sdk!.onInstallConversionData((data) async {
      final raw = data['payload'] ?? data;
      final payload = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};

      if (payload['af_status'] == 'Organic') {
        await Future.delayed(
          Duration(seconds: ProjectConstants.gcdRetryDelaySeconds),
        );
        final retry = await _pullGcdSnapshot();
        _installPayload = retry ?? payload;
      } else {
        _installPayload = payload;
      }

      if (!_installGate.isCompleted) {
        _installGate.complete(_installPayload ?? <String, dynamic>{});
      }
    });

    _sdk!.onAppOpenAttribution((data) {
      final raw = data['payload'] ?? data;
      if (raw is Map) {
        _openPayload = Map<String, dynamic>.from(raw);
      }
    });

    _sdk!.onDeepLinking((result) {
      final dl = result.deepLink;
      if (dl != null) {
        _deepLinkPayload = Map<String, dynamic>.from(dl.clickEvent);
      }
      if (!_deepLinkGate.isCompleted) _deepLinkGate.complete();
    });

    await _sdk!.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
  }

  Future<Map<String, dynamic>?> _pullGcdSnapshot() async {
    try {
      final uid = await deviceUid();
      if (uid == null || uid.isEmpty) return null;
      final appId = Platform.isIOS
          ? ProjectConstants.attributionAppId
          : ProjectConstants.bundleId;
      final url = buildGcdLookupUrl(appId, uid);
      if (url.isEmpty) return null;

      final response = await outboundHttp
          .get(
            Uri.parse(url),
            headers: {'authorization': 'Bearer ${ProjectConstants.attributionDevKey}'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> awaitInstallData() {
    return _installGate.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => <String, dynamic>{},
    );
  }

  Future<void> awaitDeepLink() {
    return _deepLinkGate.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
  }

  Future<String?> deviceUid() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> composeBody({
    required String localeTag,
    String? fcmToken,
  }) async {
    final body = <String, dynamic>{};
    body.addAll(_installPayload ?? {});
    _deepLinkPayload?.forEach((k, v) => body.putIfAbsent(k, () => v));
    _openPayload?.forEach((k, v) => body.putIfAbsent(k, () => v));

    body['af_id'] = await deviceUid() ?? '';
    body['bundle_id'] = ProjectConstants.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = ProjectConstants.storeId;
    body['locale'] = localeTag;

    if (fcmToken != null && fcmToken.isNotEmpty) {
      body['push_token'] = fcmToken;
    }
    final projectNo = ProjectConstants.firebaseProjectNumber;
    if (projectNo.isNotEmpty) {
      body['firebase_project_id'] = projectNo;
    }

    if (kDebugMode) {
      debugPrint('[AttributionBridge] body=${jsonEncode(body)}');
    }
    return body;
  }
}
