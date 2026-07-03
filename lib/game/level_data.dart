import 'dart:math';
import 'package:flutter/material.dart';

enum ObstacleType { fence, mill, water, dirt, trampoline }

/// Physics hitbox sizes as fractions of the drawn sprite rect. These are hand
/// tuned to match the ACTUAL visible content of each asset (because sprites
/// have transparent padding around them).
class HitboxRatio {
  /// For circular obstacles — radius as a fraction of the drawn rect's
  /// shortest side.
  final double radius;
  /// For rectangular obstacles (fence) — width & height fractions of the
  /// drawn rect.
  final double rectW;
  final double rectH;
  const HitboxRatio.circle(this.radius) : rectW = 0, rectH = 0;
  const HitboxRatio.rect(this.rectW, this.rectH) : radius = 0;
}

// NOTE: hitbox ratios below are relative to the DRAWN sprite rect. Sprites
// are drawn from a cropped source region in the painter, so what you SEE on
// screen fills (approximately) the whole drawn rect. Ratios are tuned so the
// physics boundary sits INSIDE the visual sprite (never outside), preventing
// "invisible walls".
HitboxRatio hitboxOf(ObstacleType t) {
  switch (t) {
    case ObstacleType.fence:
      // Very tight fence hitbox — the ball must clearly overlap the wooden
      // planks to bounce; brushing the visible edges lets it pass through.
      return const HitboxRatio.rect(0.66, 0.42);
    case ObstacleType.trampoline:
      return const HitboxRatio.circle(0.42);
    case ObstacleType.water:
      return const HitboxRatio.circle(0.44);
    case ObstacleType.mill:
      // Solid core only. Wind zone is handled separately.
      return const HitboxRatio.circle(0.22);
    case ObstacleType.dirt:
      return const HitboxRatio.circle(0.44);
  }
}

class ObstacleSpec {
  final ObstacleType type;
  /// Position and size are in normalized coordinates (0..1) relative to the
  /// playfield (portrait) so the level layout scales to any screen.
  final Offset position;
  final Size size;
  final double rotation; // radians

  const ObstacleSpec({
    required this.type,
    required this.position,
    required this.size,
    this.rotation = 0,
  });
}

class LevelSpec {
  final int index;
  final String title;
  final int par;
  /// Ball start (bottom area).
  final Offset ballStart;
  /// Hole position (upper area — "farther from start").
  final Offset holePosition;
  final List<ObstacleSpec> obstacles;

  const LevelSpec({
    required this.index,
    required this.title,
    required this.par,
    required this.ballStart,
    required this.holePosition,
    required this.obstacles,
  });
}

/// Generates 40 hand-tuned levels of increasing difficulty. Obstacles are
/// pseudo-randomly placed with a deterministic seed per level so runs are
/// reproducible but levels feel distinct.
List<LevelSpec> buildLevels() {
  final List<LevelSpec> out = [];
  for (int i = 1; i <= 40; i++) {
    out.add(_buildLevel(i));
  }
  return out;
}

// Per-level obstacle counts across 40 levels. Because obstacles are large,
// each level has a tight cap so the playfield stays playable. Difficulty
// increases via mix, positioning and rotated fences rather than sheer count.
//                            L1 L2 L3 L4 L5  L6 L7 L8 L9 L10  L11 L12 L13 L14 L15  L16 L17 L18 L19 L20  L21 L22 L23 L24 L25  L26 L27 L28 L29 L30  L31 L32 L33 L34 L35  L36 L37 L38 L39 L40
const _fencesPerLevel = <int>[ 0, 1, 1, 1, 2,   1, 1, 2, 1, 2,    1,  2,  1,  2,  1,    2,  1,  3,  2,  1,    2,  2,  1,  2,  2,    2,  3,  2,  1,  3,    2,  2,  3,  2,  1,    2,  3,  2,  3,  3];
const _trampsPerLevel = <int>[ 0, 0, 1, 1, 1,   1, 1, 1, 1, 1,    1,  1,  2,  1,  1,    1,  2,  1,  1,  2,    1,  1,  2,  1,  2,    2,  1,  2,  2,  1,    2,  1,  2,  2,  2,    1,  2,  2,  1,  2];
const _waterPerLevel  = <int>[ 0, 0, 0, 1, 0,   1, 1, 1, 1, 1,    1,  1,  1,  1,  2,    1,  1,  0,  1,  1,    2,  1,  1,  2,  1,    1,  2,  1,  1,  1,    2,  2,  1,  1,  2,    2,  1,  2,  2,  2];
const _millsPerLevel  = <int>[ 0, 0, 0, 0, 0,   0, 1, 0, 1, 0,    1,  0,  0,  1,  1,    1,  1,  1,  1,  1,    1,  2,  1,  1,  1,    1,  1,  2,  1,  2,    1,  2,  1,  2,  1,    2,  1,  1,  2,  2];
const _dirtPerLevel   = <int>[ 1, 1, 1, 1, 1,   1, 0, 1, 1, 1,    1,  2,  1,  0,  1,    1,  1,  1,  1,  1,    0,  0,  1,  1,  1,    1,  0,  0,  1,  1,    0,  1,  1,  0,  1,    1,  1,  0,  1,  0];

// Sprite sizes as fractions of the playfield's shortest side. Bumped per
// user request: fence & water ×1.5, mill & trampoline ~×1.7. (Full 2× on the
// biggest sprites would leave no room for other obstacles even on late
// levels, so mill/trampoline were nudged down slightly.)
const _fenceSize = Size(0.45, 0.225); // 1.5× previous
const _trampSize = Size(0.38, 0.38);  // ~1.7× previous
const _waterSize = Size(0.39, 0.39);  // 1.5× previous
const _millSize  = Size(0.40, 0.40);  // ~1.7× previous
const _dirtSize  = Size(0.22, 0.22);  // unchanged

class _Request {
  final ObstacleType type;
  final Size size;
  final double rotation;
  _Request(this.type, this.size, {this.rotation = 0});
}

LevelSpec _buildLevel(int i) {
  final rnd = Random(1000 + i * 37);
  final ballStart = Offset(0.3 + rnd.nextDouble() * 0.4, 0.86);
  final holePosition = Offset(0.25 + rnd.nextDouble() * 0.5, 0.10);

  final idx = i - 1;
  final requests = <_Request>[
    for (int k = 0; k < _fencesPerLevel[idx]; k++)
      _Request(
        ObstacleType.fence,
        _fenceSize,
        rotation: rnd.nextBool() ? 0.0 : (rnd.nextDouble() - 0.5) * 1.2,
      ),
    for (int k = 0; k < _trampsPerLevel[idx]; k++)
      _Request(ObstacleType.trampoline, _trampSize),
    for (int k = 0; k < _waterPerLevel[idx]; k++)
      _Request(ObstacleType.water, _waterSize),
    for (int k = 0; k < _millsPerLevel[idx]; k++)
      _Request(ObstacleType.mill, _millSize),
    for (int k = 0; k < _dirtPerLevel[idx]; k++)
      _Request(ObstacleType.dirt, _dirtSize),
  ]..shuffle(rnd);

  final obstacles = <ObstacleSpec>[];
  // Approximate portrait aspect ratio (width / height) used to convert
  // sprite sizes (in shortest-side units) into position-space (0..1 x/y)
  // rectangles. Prevents the algorithm from overestimating obstacle height.
  const aspect = 0.56;

  // "Hard" forbidden zones (start and hole) — never allow overlap.
  final hardBanned = <Rect>[
    Rect.fromCenter(center: ballStart, width: 0.30, height: 0.18),
    Rect.fromCenter(center: holePosition, width: 0.30, height: 0.20),
  ];
  final softBanned = <Rect>[];

  ObstacleSpec? tryPlace(_Request req, double softPad) {
    // Convert sprite size (fraction of shortestSide) into position-space
    // (fraction of width/height respectively).
    final rectW = req.size.width;
    final rectH = req.size.height * aspect;
    for (int a = 0; a < 80; a++) {
      final x = 0.08 + rnd.nextDouble() * 0.84;
      final y = 0.15 + rnd.nextDouble() * 0.70;
      final pos = Offset(x, y);
      final hardRect = Rect.fromCenter(
        center: pos,
        width: rectW + 0.02,
        height: rectH + 0.02,
      );
      final softRect = Rect.fromCenter(
        center: pos,
        width: rectW + softPad,
        height: rectH + softPad,
      );
      bool ok = true;
      for (final f in hardBanned) {
        if (f.overlaps(hardRect)) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      for (final f in softBanned) {
        if (f.overlaps(softRect)) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      softBanned.add(hardRect);
      return ObstacleSpec(
        type: req.type,
        position: pos,
        size: req.size,
        rotation: req.rotation,
      );
    }
    return null;
  }

  for (final req in requests) {
    // Try strict spacing first, then progressively looser so every obstacle
    // ultimately finds a spot.
    ObstacleSpec? placed = tryPlace(req, 0.04);
    placed ??= tryPlace(req, 0.02);
    placed ??= tryPlace(req, 0.0);
    placed ??= tryPlace(req, -0.02); // last resort: allow slight overlap
    if (placed != null) obstacles.add(placed);
  }

  final par = 2 + (i ~/ 2);
  return LevelSpec(
    index: i,
    title: 'Level $i',
    par: par,
    ballStart: ballStart,
    holePosition: holePosition,
    obstacles: obstacles,
  );
}
