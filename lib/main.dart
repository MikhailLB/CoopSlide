import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bootstrap.dart';
import 'core/alert_hub.dart';
import 'core/attribution_bridge.dart';
import 'core/config_gateway.dart';
import 'core/net_sensor.dart';
import 'core/outbound_http.dart';
import 'core/session_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );
  } catch (_) {}

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  await outboundHttp.bootstrap();

  final store = SessionStore();
  await store.warmUp();

  final netSensor = NetSensor();
  final attribution = AttributionBridge();
  final gateway = ConfigGateway(store);
  final alerts = AlertHub(store);

  runApp(
    CoopSlideBootstrap(
      store: store,
      netSensor: netSensor,
      attribution: attribution,
      gateway: gateway,
      alerts: alerts,
    ),
  );
}
