import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'menu_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  double _progress = 0.0;
  int _dotCount = 1;
  Timer? _dotTimer;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    // Allow both orientations only on loading screen.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _startLoading();
  }

  void _startLoading() {
    _dotTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      setState(() => _dotCount = (_dotCount % 3) + 1);
    });

    // The progress bar smoothly fills over ~2.4 seconds, then reaches 100%
    // right before we navigate to the menu (as required).
    const totalMs = 2400;
    const tickMs = 40;
    int elapsed = 0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: tickMs), (
      t,
    ) async {
      elapsed += tickMs;
      if (!mounted) return;
      // Curve: reach ~92% quickly then slow, so 100% only happens on final tick.
      double p = elapsed / totalMs;
      double eased;
      if (p < 0.85) {
        eased = (p / 0.85) * 0.92;
      } else {
        eased = 0.92 + ((p - 0.85) / 0.15) * 0.07; // up to ~0.99
      }
      setState(() => _progress = eased.clamp(0.0, 0.99));

      if (elapsed >= totalMs) {
        t.cancel();
        _dotTimer?.cancel();
        setState(() => _progress = 1.0);
        // Small hold so user visually perceives the full bar.
        await Future<void>.delayed(const Duration(milliseconds: 220));
        if (!mounted) return;
        // Lock to portrait for the rest of the app (gameplay is strictly vertical).
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 350),
            pageBuilder: (_, _, _) => const MenuScreen(),
            transitionsBuilder: (_, anim, _, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _dotTimer?.cancel();
    _progressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isPortrait = orientation == Orientation.portrait;
    final bgPath = isPortrait
        ? 'assets/vertical_loading.jpg'
        : 'assets/hor_loading.jpg';

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(bgPath, fit: BoxFit.cover),
          // Soft dark gradient at the bottom for readability.
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
                bottom: isPortrait ? 80 : 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LoadingText(dotCount: _dotCount),
                  const SizedBox(height: 14),
                  _ProgressBar(progress: _progress),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingText extends StatelessWidget {
  final int dotCount;
  const _LoadingText({required this.dotCount});

  @override
  Widget build(BuildContext context) {
    final dots = '.' * dotCount;
    return Text(
      'Loading$dots',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        shadows: [
          Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  const _ProgressBar({required this.progress});

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
      // Align to the LEFT edge and use a FractionallySizedBox so the fill
      // always grows strictly from left to right.
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress.clamp(0.0, 1.0),
          heightFactor: 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            curve: Curves.easeOut,
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
