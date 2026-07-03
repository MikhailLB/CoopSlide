import 'package:flutter/material.dart';

import '../core/alert_hub.dart';
import '../core/net_sensor.dart';
import '../core/session_store.dart';
import '../setup/project_constants.dart';
import 'portal_stage.dart' deferred as portal;

class AlertsOptIn extends StatefulWidget {
  final SessionStore store;
  final AlertHub alerts;
  final NetSensor netSensor;
  final String portalUrl;

  const AlertsOptIn({
    super.key,
    required this.store,
    required this.alerts,
    required this.netSensor,
    required this.portalUrl,
  });

  @override
  State<AlertsOptIn> createState() => _AlertsOptInState();
}

class _AlertsOptInState extends State<AlertsOptIn> {
  bool _acceptBusy = false;

  Future<void> _snoozePrompt() async {
    final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        ProjectConstants.alertsSnoozeSeconds;
    await widget.store.writeAlertsSnoozeUntil(until);
  }

  Future<void> _enterPortal() async {
    await portal.loadLibrary();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => portal.PortalStage(
          url: widget.portalUrl,
          store: widget.store,
          alerts: widget.alerts,
          netSensor: widget.netSensor,
        ),
      ),
    );
  }

  Future<void> _onAccept() async {
    if (_acceptBusy) return;
    setState(() => _acceptBusy = true);
    final granted = await widget.alerts.askUserForAlerts();
    if (!granted) await _snoozePrompt();
    if (!mounted) return;
    await _enterPortal();
  }

  Future<void> _onSkip() async {
    await _snoozePrompt();
    if (!mounted) return;
    await _enterPortal();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final art = landscape
        ? 'assets/notif/notif_hor.webp'
        : 'assets/notif/notif_vert.webp';

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(art, fit: BoxFit.cover),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: landscape ? size.width * 0.34 : size.width * 0.08,
            right: landscape ? size.width * 0.34 : size.width * 0.08,
            bottom: landscape ? size.height * 0.08 : size.height * 0.07,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AcceptChip(
                  busy: _acceptBusy,
                  onTap: _onAccept,
                  compact: landscape,
                ),
                SizedBox(height: landscape ? 10 : 16),
                _SkipChip(onTap: _onSkip, compact: landscape),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AcceptChip extends StatefulWidget {
  final VoidCallback onTap;
  final bool compact;
  final bool busy;
  const _AcceptChip({
    required this.onTap,
    required this.compact,
    required this.busy,
  });

  @override
  State<_AcceptChip> createState() => _AcceptChipState();
}

class _AcceptChipState extends State<_AcceptChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (!widget.busy) widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          height: widget.compact ? 48 : 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _pressed
                  ? [const Color(0xFF6BCB3E), const Color(0xFF4FA828)]
                  : [const Color(0xFF7ED957), const Color(0xFF5CBF3A)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5CBF3A).withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: widget.busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Accept',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.compact ? 17 : 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _SkipChip extends StatefulWidget {
  final VoidCallback onTap;
  final bool compact;
  const _SkipChip({required this.onTap, required this.compact});

  @override
  State<_SkipChip> createState() => _SkipChipState();
}

class _SkipChipState extends State<_SkipChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          height: widget.compact ? 44 : 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _pressed
                  ? [const Color(0xFF6BCB3E), const Color(0xFF4FA828)]
                  : [const Color(0xFF7ED957), const Color(0xFF5CBF3A)],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5CBF3A).withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'Skip',
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.compact ? 16 : 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
