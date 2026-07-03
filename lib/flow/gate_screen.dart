import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/alert_hub.dart';
import '../core/attribution_bridge.dart';
import '../core/config_gateway.dart';
import '../core/net_sensor.dart';
import '../core/session_store.dart';
import '../data/route_decision.dart';
import '../screens/menu_screen.dart';
import 'alerts_opt_in.dart';
import 'offline_gate.dart';
import 'portal_stage.dart' deferred as portal;

class GateScreen extends StatefulWidget {
  final SessionStore store;
  final NetSensor netSensor;
  final AttributionBridge attribution;
  final ConfigGateway gateway;
  final AlertHub alerts;

  const GateScreen({
    super.key,
    required this.store,
    required this.netSensor,
    required this.attribution,
    required this.gateway,
    required this.alerts,
  });

  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> {
  double _progress = 0.0;
  int _dots = 1;
  Timer? _dotTimer;
  Timer? _progressTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _beginVisualLoad();
    _orchestrate();
  }

  void _beginVisualLoad() {
    _dotTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      setState(() => _dots = (_dots % 3) + 1);
    });

    const totalMs = 2600;
    const tickMs = 40;
    var elapsed = 0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: tickMs), (t) {
      elapsed += tickMs;
      if (!mounted) return;
      final p = elapsed / totalMs;
      final eased = p < 0.85 ? (p / 0.85) * 0.92 : 0.92 + ((p - 0.85) / 0.15) * 0.07;
      setState(() => _progress = eased.clamp(0.0, 0.99));
    });
  }

  Future<void> _finishBar() async {
    _dotTimer?.cancel();
    _progressTimer?.cancel();
    if (!mounted) return;
    setState(() => _progress = 1.0);
    await Future<void>.delayed(const Duration(milliseconds: 220));
  }

  Future<void> _orchestrate() async {
    widget.alerts.onTokenRotated = _onTokenRotated;
    await widget.alerts.bootstrap().catchError((_) {});

    final route = widget.store.readRoute();
    switch (route) {
      case RouteDecision.shell:
        await _resumeShell();
        break;
      case RouteDecision.native:
        await _enterNative();
        break;
      case RouteDecision.undecided:
        await _decideFirstRun();
        break;
    }
  }

  void _onTokenRotated(String token) async {
    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.attribution.composeBody(
      localeTag: locale,
      fcmToken: token,
    );
    widget.gateway.requestShell(body);
  }

  Future<void> _decideFirstRun() async {
    final online = await widget.netSensor.isOnline();
    if (!online) {
      await _finishBar();
      if (!mounted) return;
      _openOfflineGate(firstRun: true);
      return;
    }

    await widget.attribution.bootstrap();
    await Future.wait([
      widget.attribution.awaitInstallData(),
      widget.attribution.awaitDeepLink(),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.attribution.composeBody(
      localeTag: locale,
      fcmToken: widget.alerts.token,
    );
    final payload = await widget.gateway.requestShell(body);

    if (payload.accepted && payload.targetUrl != null) {
      await widget.store.writeRoute(RouteDecision.shell);
      await _finishBar();
      if (!mounted) return;
      _openShell(payload.targetUrl!);
    } else {
      await widget.store.writeRoute(RouteDecision.native);
      await _finishBar();
      if (!mounted) return;
      _openNativeMenu();
    }
  }

  Future<void> _resumeShell() async {
    final online = await widget.netSensor.isOnline();
    if (!online) {
      await _finishBar();
      if (!mounted) return;
      _openOfflineGate(firstRun: false);
      return;
    }

    final pushTarget = await widget.store.takePushTarget();
    if (pushTarget != null) {
      await _finishBar();
      if (!mounted) return;
      _openShell(pushTarget);
      return;
    }

    final cached = await widget.gateway.cachedPortalUrl();

    await widget.attribution.bootstrap();
    await Future.wait([
      widget.attribution
          .awaitInstallData()
          .timeout(const Duration(seconds: 10), onTimeout: () => {}),
      widget.attribution.awaitDeepLink(),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.attribution.composeBody(
      localeTag: locale,
      fcmToken: widget.alerts.token,
    );
    final payload = await widget.gateway.requestShell(body);

    await _finishBar();
    if (!mounted) return;

    if (payload.accepted && payload.targetUrl != null) {
      _openShell(payload.targetUrl!);
    } else if (cached != null) {
      _openShell(cached);
    } else {
      _openOfflineGate(firstRun: false);
    }
  }

  Future<void> _enterNative() async {
    await _finishBar();
    if (!mounted) return;
    _openNativeMenu();
  }

  void _openNativeMenu() {
    if (_navigated) return;
    _navigated = true;
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const MenuScreen(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _openShell(String url) async {
    if (_navigated) return;
    _navigated = true;

    await portal.loadLibrary();
    await portal.warmPortalEngine();
    if (!mounted) return;

    if (widget.store.shouldPromptForAlerts()) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AlertsOptIn(
            store: widget.store,
            alerts: widget.alerts,
            netSensor: widget.netSensor,
            portalUrl: url,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => portal.PortalStage(
            url: url,
            store: widget.store,
            alerts: widget.alerts,
            netSensor: widget.netSensor,
          ),
        ),
      );
    }
  }

  void _openOfflineGate({required bool firstRun}) {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OfflineGate(
          retryBuilder: (_) => GateScreen(
            store: widget.store,
            netSensor: widget.netSensor,
            attribution: widget.attribution,
            gateway: widget.gateway,
            alerts: widget.alerts,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.alerts.onTokenRotated = null;
    _dotTimer?.cancel();
    _progressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final portrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final bg = portrait
        ? 'assets/vertical_loading.jpg'
        : 'assets/hor_loading.jpg';
    final dots = '.' * _dots;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(bg, fit: BoxFit.cover),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.35),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                left: 32,
                right: 32,
                bottom: portrait ? 80 : 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Loading$dots',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _LoadBar(progress: _progress),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadBar extends StatelessWidget {
  final double progress;
  const _LoadBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress.clamp(0.0, 1.0),
          heightFactor: 1.0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFFFFE066), Color(0xFFFFA630)],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFA630).withValues(alpha: 0.55),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
