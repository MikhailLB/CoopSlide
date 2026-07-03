import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'level_data.dart';

class GameImages {
  final ui.Image chickenBall;
  final ui.Image chickenFly;
  final ui.Image hole;
  final ui.Image fence;
  final ui.Image mill;
  final ui.Image water;
  final ui.Image dirt;
  final ui.Image trampoline;
  final ui.Image bg;

  GameImages({
    required this.chickenBall,
    required this.chickenFly,
    required this.hole,
    required this.fence,
    required this.mill,
    required this.water,
    required this.dirt,
    required this.trampoline,
    required this.bg,
  });
}

class GamePainter extends CustomPainter {
  final GameImages images;
  final LevelSpec level;
  final Offset ballPos; // pixel coords
  final double ballHeight; // z (0 on ground)
  final double ballRotation; // radians (visual spin)
  final bool isFlying; // in-air => use chickenFly sprite
  final double millAngle; // rotation of mill blades
  final Offset? aimStart; // pixels
  final Offset? aimEnd; // pixels
  final double ballRadius;
  final bool ballInHole;

  GamePainter({
    required this.images,
    required this.level,
    required this.ballPos,
    required this.ballHeight,
    required this.ballRotation,
    required this.isFlying,
    required this.millAngle,
    required this.aimStart,
    required this.aimEnd,
    required this.ballRadius,
    required this.ballInHole,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background — cover fit.
    paintImageCover(canvas, size, images.bg);

    // Hole (rendered under the ball so ball can sink into it).
    final holePx = _norm(level.holePosition, size);
    // Hole size ×1.2 vs previous.
    final holeSize = size.shortestSide * 0.288;
    _drawSprite(
      canvas,
      images.hole,
      Rect.fromCenter(center: holePx, width: holeSize, height: holeSize),
    );

    // Obstacles (except mill blades which we redraw with rotation).
    for (final o in level.obstacles) {
      _drawObstacle(canvas, size, o);
    }

    // Aim line (from ball, if aiming).
    if (aimStart != null && aimEnd != null && !ballInHole) {
      _drawAimLine(canvas, size, aimStart!, aimEnd!);
    }

    // Ball shadow (grows with height a bit — top-down illusion).
    final shadowScale = 1.0 + ballHeight * 0.002;
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawOval(
      Rect.fromCenter(
        center: ballPos.translate(2, 4),
        width: ballRadius * 2 * shadowScale,
        height: ballRadius * 1.1 * shadowScale,
      ),
      shadowPaint,
    );

    // The chicken sprite grows a bit when it flies (z>0) for pseudo-3D pop.
    final scaleUp = 1.0 + (ballHeight / 200).clamp(0.0, 0.6);
    final r = ballRadius * scaleUp;
    final sprite = isFlying ? images.chickenFly : images.chickenBall;

    canvas.save();
    canvas.translate(ballPos.dx, ballPos.dy - ballHeight);
    canvas.rotate(ballRotation);
    _drawSprite(
      canvas,
      sprite,
      Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 2),
    );
    canvas.restore();

    // If ball is in hole — small egg-flash marker.
    if (ballInHole) {
      final p = Paint()..color = const Color(0xFFFFD54F);
      canvas.drawCircle(holePx, holeSize * 0.15, p);
    }

    // Playfield border — visible frame so the player clearly sees where the
    // chicken is confined.
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0xFF4A2C10).withValues(alpha: 0.9);
    final borderRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(3, 3, size.width - 6, size.height - 6),
      const Radius.circular(8),
    );
    canvas.drawRRect(borderRect, borderPaint);
    // A subtle inner highlight so the frame reads as a wooden fence rail.
    final innerHighlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.35);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(6, 6, size.width - 12, size.height - 12),
        const Radius.circular(6),
      ),
      innerHighlight,
    );
  }

  /// The source-rect crop (as fractions of the image size) for each obstacle
  /// type. We crop the transparent padding out of the PNG so the drawn sprite
  /// visually matches the physics hitbox as closely as possible.
  static const Map<ObstacleType, Rect> _srcCrop = {
    // Wooden fence lives in the middle band of the sprite → crop top/bottom.
    ObstacleType.fence: Rect.fromLTRB(0.03, 0.24, 0.97, 0.78),
    ObstacleType.trampoline: Rect.fromLTRB(0.06, 0.06, 0.94, 0.98),
    ObstacleType.water: Rect.fromLTRB(0.05, 0.05, 0.95, 0.95),
    ObstacleType.mill: Rect.fromLTRB(0.08, 0.05, 0.92, 0.97),
    ObstacleType.dirt: Rect.fromLTRB(0.05, 0.05, 0.95, 0.95),
  };

  void _drawObstacle(Canvas canvas, Size size, ObstacleSpec o) {
    final center = _norm(o.position, size);
    // Sizes are scaled by shortest side so sprites are never stretched by the
    // aspect ratio of the playfield.
    final s = size.shortestSide;
    final w = o.size.width * s;
    final h = o.size.height * s;

    ui.Image? img;
    switch (o.type) {
      case ObstacleType.fence:
        img = images.fence;
        break;
      case ObstacleType.mill:
        img = images.mill;
        break;
      case ObstacleType.water:
        img = images.water;
        break;
      case ObstacleType.dirt:
        img = images.dirt;
        break;
      case ObstacleType.trampoline:
        img = images.trampoline;
        break;
    }

    // Mill: draw a semi-transparent "wind" ring around the sprite so the
    // player can see the danger radius. The mill itself does NOT rotate.
    if (o.type == ObstacleType.mill) {
      final windRadius = w * 0.70;
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.4);
      canvas.drawCircle(center, windRadius, ringPaint);
      final fillPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.08);
      canvas.drawCircle(center, windRadius, fillPaint);
      _drawCropped(
        canvas,
        img,
        Rect.fromCenter(center: center, width: w, height: h),
        _srcCrop[o.type]!,
      );
      return;
    }

    final srcCrop = _srcCrop[o.type] ?? const Rect.fromLTRB(0, 0, 1, 1);

    if (o.rotation != 0) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(o.rotation);
      _drawCropped(
        canvas,
        img,
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        srcCrop,
      );
      canvas.restore();
    } else {
      _drawCropped(
        canvas,
        img,
        Rect.fromCenter(center: center, width: w, height: h),
        srcCrop,
      );
    }
  }

  /// Draws only the given fraction of the source image into `dst`, effectively
  /// cropping transparent padding on the sprite.
  void _drawCropped(
    Canvas canvas,
    ui.Image img,
    Rect dst,
    Rect srcCropRatio,
  ) {
    final src = Rect.fromLTWH(
      srcCropRatio.left * img.width,
      srcCropRatio.top * img.height,
      (srcCropRatio.right - srcCropRatio.left) * img.width,
      (srcCropRatio.bottom - srcCropRatio.top) * img.height,
    );
    canvas.drawImageRect(
      img,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  /// Draws the aiming line by tiling and warping the `line.png` texture along
  /// the vector from `start` to `end`. The line's length equals the drag
  /// distance and its **height (thickness) shrinks with the vertical
  /// component**, so a steep angle "flattens" the texture — this is the
  /// requested perspective distortion.
  void _drawAimLine(Canvas canvas, Size size, Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 6) return;

    final angle = atan2(dy, dx);
    final baseH = size.shortestSide * 0.045; // slim shaft
    final tilt = (dy.abs() / (len)).clamp(0.0, 1.0);
    final h = baseH * (1.0 - 0.30 * tilt);

    canvas.save();
    canvas.translate(start.dx, start.dy);
    canvas.rotate(angle);

    final arrowW = h * 2.4; // arrow head length
    final lineLen = (len - arrowW).clamp(0.0, double.infinity);

    if (lineLen > 3) {
      // Line shaft — orange rounded rectangle with a thin white outline.
      final shaftRect = Rect.fromLTWH(0, -h / 2, lineLen, h);
      final shaftShape = RRect.fromRectAndRadius(
        shaftRect,
        Radius.circular(h / 2),
      );
      canvas.drawRRect(
        shaftShape,
        Paint()..color = const Color(0xFFFFA630),
      );
      canvas.drawRRect(
        shaftShape,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }

    // Compact arrow head — noticeably wider than the shaft.
    final headHalf = h * 1.35;
    final headBase = lineLen;
    final path = Path()
      ..moveTo(len, 0)
      ..lineTo(headBase, -headHalf)
      ..lineTo(headBase, headHalf)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFA630));
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    canvas.restore();
  }

  Offset _norm(Offset o, Size s) => Offset(o.dx * s.width, o.dy * s.height);

  void _drawSprite(Canvas canvas, ui.Image img, Rect dst) {
    final src = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    canvas.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.high);
  }

  void paintImageCover(Canvas canvas, Size size, ui.Image img) {
    final srcAr = img.width / img.height;
    final dstAr = size.width / size.height;
    Rect src;
    if (srcAr > dstAr) {
      // image wider — crop sides
      final newW = img.height * dstAr;
      final x = (img.width - newW) / 2;
      src = Rect.fromLTWH(x, 0, newW, img.height.toDouble());
    } else {
      final newH = img.width / dstAr;
      final y = (img.height - newH) / 2;
      src = Rect.fromLTWH(0, y, img.width.toDouble(), newH);
    }
    canvas.drawImageRect(
      img,
      src,
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(covariant GamePainter old) {
    return true;
  }
}
