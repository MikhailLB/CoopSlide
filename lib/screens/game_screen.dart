import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../game/game_painter.dart';
import '../game/level_data.dart';

class GameScreen extends StatefulWidget {
  final LevelSpec level;
  final int totalLevels;

  const GameScreen({
    super.key,
    required this.level,
    required this.totalLevels,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  GameImages? _images;
  late Ticker _ticker;
  Duration _lastTick = Duration.zero;

  // Playfield size in pixels; recomputed on layout.
  Size _fieldSize = Size.zero;

  // Ball state.
  late Offset _ballPos;
  Offset _ballVel = Offset.zero;
  double _ballZ = 0; // "height" from top-down; not real 3D
  double _ballVz = 0;
  double _ballRot = 0;
  int _jumpsUsed = 0; // resets on landing
  bool _stopped = true;

  // Aiming.
  Offset? _aimStartLocal; // in field coordinates
  Offset? _aimCurrentLocal;
  static const double _maxAimLen = 260;
  static const double _maxShotSpeed = 1400.0; // px/sec

  int _shots = 0;
  bool _levelDone = false;
  double _millAngle = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    Future<ui.Image> load(String path) async {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return frame.image;
    }

    final imgs = await Future.wait([
      load('assets/chikenball.png'),
      load('assets/chikenfly.png'),
      load('assets/hole.png'),
      load('assets/fence.png'),
      load('assets/mill.png'),
      load('assets/water.png'),
      load('assets/dirt.png'),
      load('assets/trampoline.png'),
      load('assets/bggamenew.jpg'),
    ]);

    if (!mounted) return;
    setState(() {
      _images = GameImages(
        chickenBall: imgs[0],
        chickenFly: imgs[1],
        hole: imgs[2],
        fence: imgs[3],
        mill: imgs[4],
        water: imgs[5],
        dirt: imgs[6],
        trampoline: imgs[7],
        bg: imgs[8],
      );
    });
  }

  void _resetBall() {
    _ballPos = Offset(
      widget.level.ballStart.dx * _fieldSize.width,
      widget.level.ballStart.dy * _fieldSize.height,
    );
    _ballVel = Offset.zero;
    _ballZ = 0;
    _ballVz = 0;
    _ballRot = 0;
    _jumpsUsed = 0;
    _stopped = true;
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (_images == null || _fieldSize == Size.zero || _levelDone) return;

    _millAngle += dt * 1.2;

    // Vertical (z) physics — used when flying.
    if (_ballZ > 0 || _ballVz > 0) {
      _ballVz -= 900 * dt; // "gravity"
      _ballZ += _ballVz * dt;
      if (_ballZ <= 0) {
        _ballZ = 0;
        _ballVz = 0;
        _jumpsUsed = 0; // landed — reset jumps
      }
    }

    // Wind zones (mills) can push the ball even when it's still.
    _applyWind(dt);

    if (_ballVel.distance > 0.5) {
      _stopped = false;
      final r = _ballRadius();
      Offset newPos = _ballPos + _ballVel * dt;

      // Bounce off field edges.
      if (newPos.dx - r < 0) {
        newPos = Offset(r, newPos.dy);
        _ballVel = Offset(-_ballVel.dx * 0.7, _ballVel.dy);
      } else if (newPos.dx + r > _fieldSize.width) {
        newPos = Offset(_fieldSize.width - r, newPos.dy);
        _ballVel = Offset(-_ballVel.dx * 0.7, _ballVel.dy);
      }
      if (newPos.dy - r < 0) {
        newPos = Offset(newPos.dx, r);
        _ballVel = Offset(_ballVel.dx, -_ballVel.dy * 0.7);
      } else if (newPos.dy + r > _fieldSize.height) {
        newPos = Offset(newPos.dx, _fieldSize.height - r);
        _ballVel = Offset(_ballVel.dx, -_ballVel.dy * 0.7);
      }

      _ballPos = newPos;
      _handleObstacles();

      // Friction: much stronger on ground, near-zero in air.
      final friction = _ballZ > 5 ? 0.35 : 1.6;
      final speed = _ballVel.distance;
      final newSpeed = max(0.0, speed - friction * dt * speed);
      _ballVel = speed > 0
          ? _ballVel * (newSpeed / speed)
          : Offset.zero;

      // Spin
      _ballRot += speed * dt * 0.02;

      if (_ballVel.distance < 8 && _ballZ <= 0) {
        _ballVel = Offset.zero;
        _stopped = true;
      }
    } else if (_ballZ <= 0) {
      _stopped = true;
    }

    // Check hole capture.
    _checkHole();

    setState(() {});
  }

  // Chicken visual radius as a fraction of shortest side (×1.3 vs previous).
  double _ballRadius() => _fieldSize.shortestSide * 0.0845;

  void _applyWind(double dt) {
    for (final o in widget.level.obstacles) {
      if (o.type != ObstacleType.mill) continue;
      final center = Offset(
        o.position.dx * _fieldSize.width,
        o.position.dy * _fieldSize.height,
      );
      final s = _fieldSize.shortestSide;
      final w = o.size.width * s;
      // Wind extends ~40% beyond the mill sprite.
      final windRadius = w * 0.70;
      final delta = _ballPos - center;
      final dist = delta.distance;
      if (dist < windRadius) {
        final dir = dist == 0
            ? const Offset(0, -1)
            : delta / dist;
        // Strength grows toward the center of the wind zone.
        final strength = 1.0 - (dist / windRadius);
        // 2200 px/sec^2 near the core — noticeably launches the ball.
        _ballVel = _ballVel + dir * (2200 * strength * dt);
      }
    }
  }

  void _handleObstacles() {
    final r = _ballRadius();
    final level = widget.level;
    for (final o in level.obstacles) {
      final center = Offset(
        o.position.dx * _fieldSize.width,
        o.position.dy * _fieldSize.height,
      );
      final s = _fieldSize.shortestSide;
      final drawW = o.size.width * s;
      final drawH = o.size.height * s;
      final hb = hitboxOf(o.type);
      // Hitbox size scales the drawn sprite by the sprite-specific ratio.
      final hitR = hb.radius * (drawW < drawH ? drawW : drawH); // circle radius
      final hitW = hb.rectW * drawW;
      final hitH = hb.rectH * drawH;

      switch (o.type) {
        case ObstacleType.trampoline:
          final dist = (_ballPos - center).distance;
          if (dist < hitR + r && _ballZ < 40) {
            _ballVz = 620.0;
            _jumpsUsed = 0;
            final dir = _ballPos - center;
            _ballPos = center +
                (dir.distance == 0
                    ? const Offset(0, -1)
                    : dir / dir.distance) *
                    (hitR + r + 2);
          }
          break;
        case ObstacleType.water:
          final dist = (_ballPos - center).distance;
          if (dist < hitR && _ballZ < 8) {
            _resetBall();
            return;
          }
          break;
        case ObstacleType.dirt:
          final dist = (_ballPos - center).distance;
          if (dist < hitR && _ballZ < 6) {
            _ballVel = _ballVel * 0.85;
          }
          break;
        case ObstacleType.fence:
          if (_ballZ > 45) break;
          _rectBounce(center, hitW, hitH, o.rotation);
          break;
        case ObstacleType.mill:
          // Wind is applied globally in _applyWind(); here we only handle the
          // solid core in the middle of the mill.
          final dist = (_ballPos - center).distance;
          if (_ballZ < 80 && dist < hitR + r) {
            final dir = dist == 0
                ? const Offset(0, -1)
                : (_ballPos - center) / dist;
            final vDotN = _ballVel.dx * dir.dx + _ballVel.dy * dir.dy;
            _ballVel = _ballVel - dir * (2 * vDotN) * 0.85;
            _ballPos = center + dir * (hitR + r + 1);
          }
          break;
      }
    }
  }

  void _rectBounce(Offset center, double w, double h, double rotation) {
    final r = _ballRadius();
    // Transform ball position into obstacle-local (unrotated) frame.
    final cos_ = cos(-rotation);
    final sin_ = sin(-rotation);
    final dx = _ballPos.dx - center.dx;
    final dy = _ballPos.dy - center.dy;
    final localX = dx * cos_ - dy * sin_;
    final localY = dx * sin_ + dy * cos_;

    final halfW = w / 2;
    final halfH = h / 2;

    // Closest point on rect to ball (in local space).
    final closestX = localX.clamp(-halfW, halfW);
    final closestY = localY.clamp(-halfH, halfH);
    final ddx = localX - closestX;
    final ddy = localY - closestY;
    final distSq = ddx * ddx + ddy * ddy;
    if (distSq < r * r) {
      final dist = sqrt(distSq);
      Offset normalLocal;
      if (dist < 0.0001) {
        // Ball is inside the rect — push out along shorter axis.
        if ((halfW - localX.abs()) < (halfH - localY.abs())) {
          normalLocal = Offset(localX >= 0 ? 1 : -1, 0);
        } else {
          normalLocal = Offset(0, localY >= 0 ? 1 : -1);
        }
      } else {
        normalLocal = Offset(ddx / dist, ddy / dist);
      }
      // Rotate normal back to world.
      final cosR = cos(rotation);
      final sinR = sin(rotation);
      final normalWorld = Offset(
        normalLocal.dx * cosR - normalLocal.dy * sinR,
        normalLocal.dx * sinR + normalLocal.dy * cosR,
      );
      // Reflect velocity.
      final vDotN =
          _ballVel.dx * normalWorld.dx + _ballVel.dy * normalWorld.dy;
      _ballVel = _ballVel - normalWorld * (2 * vDotN) * 0.7;
      // Push ball out along normal.
      final penetration = r - dist;
      _ballPos = _ballPos + normalWorld * (penetration + 0.5);
    }
  }

  void _checkHole() {
    final holePx = Offset(
      widget.level.holePosition.dx * _fieldSize.width,
      widget.level.holePosition.dy * _fieldSize.height,
    );
    final dist = (_ballPos - holePx).distance;
    // Match new visual hole size (0.288 × shortestSide) — capture radius scaled ×1.2 too.
    final captureR = _fieldSize.shortestSide * 0.108;
    if (dist < captureR && _ballZ < 20 && _ballVel.distance < 800) {
      _onLevelComplete();
    }
  }

  Future<void> _onLevelComplete() async {
    if (_levelDone) return;
    setState(() {
      _levelDone = true;
      _ballVel = Offset.zero;
      _stopped = true;
    });
    // Persist progress and compute the new unlocked level.
    final sp = await SharedPreferences.getInstance();
    final unlocked = sp.getInt('unlocked_level') ?? 1;
    final newUnlocked = min(widget.totalLevels, widget.level.index + 1);
    if (widget.level.index >= unlocked) {
      await sp.setInt('unlocked_level', newUnlocked);
    }
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LevelCompleteDialog(
        level: widget.level,
        shots: _shots,
        onNext: widget.level.index < widget.totalLevels
            ? () {
                Navigator.of(context).pop();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => GameScreen(
                      level: buildLevels()[widget.level.index],
                      totalLevels: widget.totalLevels,
                    ),
                  ),
                );
              }
            : null,
        onMenu: () {
          Navigator.of(context).pop();
          // Return the newly-unlocked level so the LevelSelect screen can
          // update its state IMMEDIATELY (no async storage round-trip).
          Navigator.of(context).pop(newUnlocked);
        },
        onReplay: () {
          Navigator.of(context).pop();
          setState(() {
            _shots = 0;
            _levelDone = false;
            _resetBall();
          });
        },
      ),
    );
  }

  // Called when user taps once (single tap during flight => jump).
  void _onTap() {
    if (_levelDone) return;
    // Double-jump: allow up to 2 impulses while airborne / just launched.
    if (_ballZ > 5 || _ballVel.distance > 40) {
      if (_jumpsUsed < 2) {
        _ballVz = 560.0 - _jumpsUsed * 120.0;
        _jumpsUsed++;
      }
    }
  }

  // Drag handlers for shot.
  void _onPanStart(DragStartDetails d) {
    if (!_stopped || _levelDone) return;
    _aimStartLocal = _localOf(d.globalPosition);
    _aimCurrentLocal = _aimStartLocal;
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_aimStartLocal == null) return;
    _aimCurrentLocal = _localOf(d.globalPosition);
    setState(() {});
  }

  void _onPanEnd(DragEndDetails d) {
    if (_aimStartLocal == null || _aimCurrentLocal == null) return;
    final drag = _aimCurrentLocal! - _aimStartLocal!;
    final len = drag.distance;
    if (len > 12) {
      // Shot direction: OPPOSITE the drag (like slingshot / Angry Birds).
      final dir = -drag / drag.distance;
      final power = (len / _maxAimLen).clamp(0.0, 1.0);
      _ballVel = dir * (_maxShotSpeed * power);
      // Small automatic hop so the chicken briefly "flies".
      _ballVz = 260 * power;
      _jumpsUsed = 0;
      _shots++;
    }
    setState(() {
      _aimStartLocal = null;
      _aimCurrentLocal = null;
    });
  }

  Offset _localOf(Offset global) {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return global;
    return box.globalToLocal(global);
  }

  final GlobalKey _fieldKey = GlobalKey();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_images == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF7ED957),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final newSize = Size(constraints.maxWidth, constraints.maxHeight - 60);
            if (newSize != _fieldSize) {
              _fieldSize = newSize;
              _resetBall();
            }
            return Column(
              children: [
                _TopBar(
                  level: widget.level,
                  shots: _shots,
                  onBack: () => Navigator.of(context).pop(),
                  onReplay: () {
                    setState(() {
                      _shots = 0;
                      _levelDone = false;
                      _resetBall();
                    });
                  },
                ),
                Expanded(
                  child: GestureDetector(
                    key: _fieldKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: _onTap,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    // ClipRect guarantees nothing (chicken sprite included) is
                    // ever drawn outside the playfield — even mid-jump.
                    child: ClipRect(
                      child: CustomPaint(
                      painter: GamePainter(
                        images: _images!,
                        level: widget.level,
                        ballPos: _ballPos,
                        ballHeight: _ballZ,
                        ballRotation: _ballRot,
                        isFlying: _ballZ > 6,
                        millAngle: _millAngle,
                        aimStart: _aimStartLocal != null ? _ballPos : null,
                        aimEnd: _aimStartLocal != null &&
                                _aimCurrentLocal != null
                            ? _ballPos +
                                (_aimStartLocal! - _aimCurrentLocal!)
                                    .let((v) {
                                  final d = v.distance;
                                  if (d == 0) return v;
                                  final clamped =
                                      d.clamp(0.0, _maxAimLen).toDouble();
                                  return v * (clamped / d);
                                })
                            : null,
                        ballRadius: _ballRadius(),
                        ballInHole: _levelDone,
                      ),
                      size: Size.infinite,
                    ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

extension _OffsetLet on Offset {
  Offset let(Offset Function(Offset) f) => f(this);
}

class _TopBar extends StatelessWidget {
  final LevelSpec level;
  final int shots;
  final VoidCallback onBack;
  final VoidCallback onReplay;

  const _TopBar({
    required this.level,
    required this.shots,
    required this.onBack,
    required this.onReplay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      color: const Color(0xFF4A2C10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const SizedBox(width: 4),
          Text(
            level.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const Spacer(),
          _Chip(label: 'Par ${level.par}'),
          const SizedBox(width: 8),
          _Chip(label: 'Shots $shots'),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onReplay,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFA630),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LevelCompleteDialog extends StatelessWidget {
  final LevelSpec level;
  final int shots;
  final VoidCallback? onNext;
  final VoidCallback onMenu;
  final VoidCallback onReplay;

  const _LevelCompleteDialog({
    required this.level,
    required this.shots,
    required this.onNext,
    required this.onMenu,
    required this.onReplay,
  });

  @override
  Widget build(BuildContext context) {
    int stars;
    if (shots <= level.par) {
      stars = 3;
    } else if (shots <= level.par + 2) {
      stars = 2;
    } else {
      stars = 1;
    }
    return Dialog(
      backgroundColor: const Color(0xFFFFF3D6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Level Complete!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Color(0xFFF15A29),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final on = i < stars;
                return Icon(
                  on ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: on ? const Color(0xFFFFC107) : Colors.grey,
                  size: 46,
                );
              }),
            ),
            const SizedBox(height: 8),
            Text(
              'Shots: $shots  (Par ${level.par})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4A2C10),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _DialogBtn(
                  color: const Color(0xFF7ED957),
                  icon: Icons.home_rounded,
                  onTap: onMenu,
                ),
                const SizedBox(width: 12),
                _DialogBtn(
                  color: const Color(0xFF6EC1E4),
                  icon: Icons.refresh_rounded,
                  onTap: onReplay,
                ),
                if (onNext != null) ...[
                  const SizedBox(width: 12),
                  _DialogBtn(
                    color: const Color(0xFFFFA630),
                    icon: Icons.arrow_forward_rounded,
                    onTap: onNext!,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogBtn extends StatelessWidget {
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _DialogBtn({
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              offset: const Offset(0, 3),
              blurRadius: 4,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 30),
      ),
    );
  }
}
