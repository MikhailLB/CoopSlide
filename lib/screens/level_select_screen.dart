import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/level_data.dart';
import 'game_screen.dart';

class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({super.key});

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  int _unlocked = 1;
  late final List<LevelSpec> _levels;

  @override
  void initState() {
    super.initState();
    _levels = buildLevels();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final sp = await SharedPreferences.getInstance();
    setState(() {
      _unlocked = sp.getInt('unlocked_level') ?? 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bgmenu.jpg', fit: BoxFit.cover),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.20),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _CircleIconBtn(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'SELECT LEVEL',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 2,
                          shadows: [
                            Shadow(
                              color: Colors.black45,
                              offset: Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1,
                      ),
                      itemCount: _levels.length,
                      itemBuilder: (context, i) {
                        final level = _levels[i];
                        final locked = level.index > _unlocked;
                        return _LevelTile(
                          index: level.index,
                          locked: locked,
                          onTap: locked
                              ? null
                              : () async {
                                  // GameScreen pops with an int (the newly
                                  // unlocked level) when the player completes
                                  // and exits — use it to update state
                                  // instantly without hitting storage again.
                                  final result = await Navigator.of(context)
                                      .push<Object?>(
                                        MaterialPageRoute(
                                          builder: (_) => GameScreen(
                                            level: level,
                                            totalLevels: _levels.length,
                                          ),
                                        ),
                                      );
                                  if (!mounted) return;
                                  if (result is int) {
                                    setState(() {
                                      _unlocked = max(_unlocked, result);
                                    });
                                  } else {
                                    _loadProgress();
                                  }
                                },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF4A2C10)),
      ),
    );
  }
}

class _LevelTile extends StatelessWidget {
  final int index;
  final bool locked;
  final VoidCallback? onTap;
  const _LevelTile({
    required this.index,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: locked ? const Color(0xFF8B7A66) : const Color(0xFFFFA630),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              offset: const Offset(0, 3),
              blurRadius: 5,
            ),
          ],
        ),
        child: Center(
          child: locked
              ? const Icon(Icons.lock, color: Colors.white, size: 34)
              : Text(
                  '$index',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(
                        color: Colors.black38,
                        offset: Offset(0, 3),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
