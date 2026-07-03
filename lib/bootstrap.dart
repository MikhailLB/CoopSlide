import 'package:flutter/material.dart';

import 'core/alert_hub.dart';
import 'core/attribution_bridge.dart';
import 'core/config_gateway.dart';
import 'core/net_sensor.dart';
import 'core/session_store.dart';
import 'flow/gate_screen.dart';

class CoopSlideBootstrap extends StatelessWidget {
  final SessionStore store;
  final NetSensor netSensor;
  final AttributionBridge attribution;
  final ConfigGateway gateway;
  final AlertHub alerts;

  const CoopSlideBootstrap({
    super.key,
    required this.store,
    required this.netSensor,
    required this.attribution,
    required this.gateway,
    required this.alerts,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coop Slide',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF5B301)),
        useMaterial3: true,
      ),
      home: GateScreen(
        store: store,
        netSensor: netSensor,
        attribution: attribution,
        gateway: gateway,
        alerts: alerts,
      ),
    );
  }
}
