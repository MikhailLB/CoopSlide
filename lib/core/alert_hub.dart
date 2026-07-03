import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../setup/project_constants.dart';
import 'outbound_http.dart';
import 'session_store.dart';

@pragma('vm:entry-point')
Future<void> _fcmBackgroundEntry(RemoteMessage message) async {}

class AlertHub {
  final SessionStore _store;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  FirebaseMessaging? _fcm;
  String? _token;
  bool _ready = false;

  void Function(String url)? onWarmOpen;
  void Function(String token)? onTokenRotated;

  AlertHub(this._store);

  String? get token => _token;

  Future<void> bootstrap() async {
    if (_ready) return;
    try {
      _fcm = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(_fcmBackgroundEntry);

      await _setupLocalAlerts();

      _token = await _fcm!.getToken();
      _fcm!.onTokenRefresh.listen((next) {
        _token = next;
        onTokenRotated?.call(next);
      });

      FirebaseMessaging.onMessage.listen(_showForegroundAlert);
      FirebaseMessaging.onMessageOpenedApp.listen(_deliverWarmOpen);

      final cold = await _fcm!.getInitialMessage();
      if (cold != null) _stashColdOpen(cold);

      _ready = true;
    } catch (_) {
      // Firebase not wired yet — alerts stay disabled.
    }
  }

  Future<void> _setupLocalAlerts() async {
    const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == null) return;
        try {
          final map = jsonDecode(response.payload!) as Map<String, dynamic>;
          final url = map['url'] as String?;
          if (url != null && url.isNotEmpty) onWarmOpen?.call(url);
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          ProjectConstants.alertsChannelId,
          'Coop Slide Alerts',
          description: 'Game updates and offers',
          importance: Importance.high,
        ),
      );
    }
  }

  Future<bool> askUserForAlerts() async {
    if (_fcm == null) return false;
    final settings = await _fcm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      await _store.markAlertsBlockedByOs();
    }

    await _store.markAlertsGranted(granted);
    return granted;
  }

  void _showForegroundAlert(RemoteMessage message) async {
    if (!Platform.isAndroid) return;
    final note = message.notification;
    if (note == null) return;

    AndroidNotificationDetails details;
    final imageUrl = message.notification?.android?.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final bytes = await _fetchImageBytes(imageUrl);
      if (bytes != null) {
        details = AndroidNotificationDetails(
          ProjectConstants.alertsChannelId,
          'Coop Slide Alerts',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          styleInformation: BigPictureStyleInformation(
            ByteArrayAndroidBitmap(bytes),
            largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
        );
      } else {
        details = _plainDetails();
      }
    } else {
      details = _plainDetails();
    }

    final payload = message.data.isNotEmpty ? jsonEncode(message.data) : null;
    await _local.show(
      note.hashCode,
      note.title,
      note.body,
      NotificationDetails(android: details),
      payload: payload,
    );
  }

  AndroidNotificationDetails _plainDetails() {
    return AndroidNotificationDetails(
      ProjectConstants.alertsChannelId,
      'Coop Slide Alerts',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );
  }

  void _stashColdOpen(RemoteMessage message) {
    final url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) _store.stashPushTarget(url);
  }

  void _deliverWarmOpen(RemoteMessage message) {
    final url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) onWarmOpen?.call(url);
  }

  Future<Uint8List?> _fetchImageBytes(String url) async {
    try {
      final response = await outboundHttp
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }
}
