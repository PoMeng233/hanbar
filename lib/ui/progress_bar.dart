import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme_defs.dart';

/// ==================================================================
///  可动画进度条（支持横向 / 竖向，多种样式与循环动画）
///  值动画（0→目标）由外部 TweenAnimationBuilder 驱动；
///  本组件内部只跑「无限循环」的装饰动画（滴水 / 马赛克波动 /
///  条纹流动 / 光晕呼吸 / 波纹涌动），动画开关关闭时静态渲染。
/// ==================================================================
class ProgressBarView extends StatefulWidget {
  const ProgressBarView({
    super.key,
    required this.value,
    required this.orientation,
    required this.theme,
    required this.style,
    required this.isMain,
    required this.animations,
  });

  /// 当前进度（0.0 ~ 1.0）
  final double value;

  /// Axis.horizontal：横向（从左向右）；Axis.vertical：竖向（从下向上）
  final Axis orientation;

  final AppTheme theme;
  final BarStyle style;
  final bool isMain;
  final bool animations;

  @override
  State<ProgressBarView> createState() => _ProgressBarViewState();
}

class _ProgressBarViewState extends State<ProgressBarView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animations && widget.style != BarStyle.classic) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant ProgressBarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldRun =
        widget.animations && widget.style != BarStyle.classic;
    if (shouldRun && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldRun && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: _BarPainter(
              value: widget.value,
              orientation: widget.orientation,
              theme: widget.theme,
              style: widget.style,
              isMain: widget.isMain,
              animations: widget.animations,
              time: _controller.value,
            ),
          );
        },
      ),
    );
  }
}

/// 单个条目的绘制器（纯绘制，不参与布局）
class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.value,
    required this.orientation,
    required this.theme,
    required this.style,
    required this.isMain,
    required this.animations,
    required this.time,
  });

  final double value;
  final Axis orientation;
  final AppTheme theme;
  final BarStyle style;
  final bool isMain;
  final bool animations;
  final double time; // 0.0 ~ 1.0 循环相位

  List<Color> get _colors => isMain ? theme.mainGradient : theme.draftGradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (size.width < 2 || size.height < 2) return;

    // 轨道
    final radius = math.min(rect.shortestSide / 2, 8.0);
    final track = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(track, Paint()..color = theme.trackColor);

    switch (style) {
      case BarStyle.classic:
        _paintClassic(canvas, rect, radius, animated: false);
      case BarStyle.drip:
        _paintLiquid(canvas, rect, radius);
      case BarStyle.mosaic:
        _paintMosaic(canvas, rect);
      case BarStyle.striped:
        _paintStriped(canvas, rect, radius);
      case BarStyle.glow:
        _paintGlow(canvas, rect, radius);
      case BarStyle.wave:
        _paintWave(canvas, rect, radius);
    }
  }

  // ----------------------------------------------------------------
  // 基础工具
  // ----------------------------------------------------------------

  /// 填充区矩形（横向从左到右 / 竖向从下到上）
  Rect _fillRect(Rect rect) {
    final v = value.clamp(0.0, 1.0);
    if (orientation == Axis.horizontal) {
      return Rect.fromLTWH(rect.left, rect.top, rect.width * v, rect.height);
    }
    return Rect.fromLTWH(
      rect.left,
      rect.top + rect.height * (1 - v),
      rect.width,
      rect.height * v,
    );
  }

  Paint _gradientPaint(Rect target) {
    final colors = _colors;
    if (orientation == Axis.horizontal) {
      return Paint()
        ..shader = LinearGradient(colors: colors).createShader(target);
    }
    return Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: colors,
      ).createShader(target);
  }

  void _clipFill(Canvas canvas, Rect rect, VoidCallback draw) {
    final fill = _fillRect(rect);
    if (fill.width <= 0 || fill.height <= 0) return;
    canvas.save();
    canvas.clipRect(fill);
    draw();
    canvas.restore();
  }

  // ----------------------------------------------------------------
  // 经典渐变（可选流动高光 → 水滴样式的基底）
  // ----------------------------------------------------------------
  void _paintClassic(Canvas canvas, Rect rect, double radius,
      {required bool animated}) {
    final fill = _fillRect(rect);
    if (fill.width <= 0 || fill.height <= 0) return;
    final rrect = RRect.fromRectAndRadius(fill, Radius.circular(radius));
    canvas.drawRRect(rrect, _gradientPaint(fill));

    if (!animated) return;

    // 水波高光：两条随时间左右/上下流动的半透明白色波纹（仅在填充区内）
    final wavePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final t = animations ? time : 0.0;
    _clipFill(canvas, rect, () {
      for (var k = 0; k < 2; k++) {
        final phase = t * 2.0 - k * 0.5;
        final path = Path();
        if (orientation == Axis.horizontal) {
          const step = 4.0;
          var x = fill.left;
          var first = true;
          while (x <= fill.right) {
            final p = (x - fill.left) / math.max(fill.width, 1);
            final y = fill.top +
                fill.height *
                    (0.38 + 0.14 * math.sin(2 * math.pi * (p * 2.0 - phase)));
            if (first) {
              path.moveTo(x, y);
              first = false;
            } else {
              path.lineTo(x, y);
            }
            x += step;
          }
        } else {
          const step = 4.0;
          var y = fill.top;
          var first = true;
          while (y <= fill.bottom) {
            final p = (y - fill.top) / math.max(fill.height, 1);
            final x = fill.left +
                fill.width *
                    (0.38 + 0.14 * math.sin(2 * math.pi * (p * 2.0 - phase)));
            if (first) {
              path.moveTo(x, y);
              first = false;
            } else {
              path.lineTo(x, y);
            }
            y += step;
          }
        }
        canvas.drawPath(path, wavePaint);
      }
    });
  }

  // ----------------------------------------------------------------
  // 液体：重力下落、表面张力液桥、撞击凹陷与阻尼波
  // ----------------------------------------------------------------
  void _paintLiquid(Canvas canvas, Rect rect, double radius) {
    final v = value.clamp(0.0, 1.0);
    if (v <= 0) return;
    final liquidPaint = _gradientPaint(rect);
    final t = animations ? time : 0.0;

    double phaseFor(int index) => (t + index * 0.51) % 1.0;
    double impactEnvelope(double phase) {
      if (!animations || phase < 0.70) return 0;
      final age = ((phase - 0.70) / 0.30).clamp(0.0, 1.0);
      // y(t) = A * exp(-gamma*t) * cos(omega*t)
      return math.exp(-4.8 * age) * math.cos(18.0 * age);
    }

    final impact = impactEnvelope(phaseFor(0)) +
        impactEnvelope(phaseFor(1)) * 0.72;
    final fill = _fillRect(rect);

    // Draw the accumulated liquid with a damped wave at the free surface.
    final surface = Path();
    if (orientation == Axis.horizontal) {
      surface
        ..moveTo(rect.left, rect.top)
        ..lineTo(fill.right, rect.top);
      const segments = 10;
      for (var i = 0; i <= segments; i++) {
        final y = rect.top + rect.height * i / segments;
        final lateral = math.sin(i / segments * math.pi * 2.2 + t * math.pi * 2);
        final edgeX = fill.right - impact * rect.height * 0.14 * lateral;
        surface.lineTo(edgeX, y);
      }
      surface
        ..lineTo(rect.left, rect.bottom)
        ..close();
    } else {
      surface
        ..moveTo(rect.left, rect.bottom)
        ..lineTo(rect.left, fill.top);
      const segments = 12;
      for (var i = 0; i <= segments; i++) {
        final x = rect.left + rect.width * i / segments;
        final lateral = math.sin(i / segments * math.pi * 2.4 + t * math.pi * 2);
        final edgeY = fill.top + impact * rect.width * 0.13 * lateral;
        surface.lineTo(x, edgeY);
      }
      surface
        ..lineTo(rect.right, rect.bottom)
        ..close();
    }
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    canvas.drawPath(surface, liquidPaint);

    if (animations) {
      for (var i = 0; i < 2; i++) {
        _paintPhysicalDrop(canvas, rect, phaseFor(i), i, liquidPaint);
      }
    }
    canvas.restore();
  }

  void _paintPhysicalDrop(
    Canvas canvas,
    Rect rect,
    double phase,
    int index,
    Paint liquidPaint,
  ) {
    final baseRadius = math.max(1.0, rect.shortestSide * 0.10);
    final detachEnd = 0.16;
    final impactStart = 0.70;
    final mergeEnd = 0.82;
    final cross = index == 0 ? 0.30 : 0.70;
    final fill = _fillRect(rect);

    // 水滴一律从进度条最上方生成，沿重力方向下落到液面：
    // 横向=右边缘液面前沿；竖向=填充区顶面。
    final target = orientation == Axis.horizontal
        ? Offset(fill.right, rect.top + rect.height * cross)
        : Offset(rect.left + rect.width * cross, fill.top);
    final source = orientation == Axis.horizontal
        ? Offset(
            math.min(rect.right - baseRadius, fill.right + baseRadius * 0.6),
            rect.top + 1.0,
          )
        : Offset(
            rect.left + rect.width * cross,
            math.max(rect.top + 1.0, fill.top - baseRadius * 8.0),
          );

    final freeDistance = target.dy - source.dy;
    if (freeDistance < baseRadius * 1.6) return;

    final fallT = ((phase - detachEnd) / (impactStart - detachEnd))
        .clamp(0.0, 1.0);
    final detachPoint = Offset.lerp(source, target, 0.08)!;
    // 匀加速下落：s = 1/2*g*t^2，目标距离吸收 g/2。
    final gravityPosition = fallT * fallT;
    final center = phase < detachEnd
        ? Offset.lerp(source, detachPoint,
            math.pow(phase / detachEnd, 2).toDouble())!
        : Offset.lerp(detachPoint, target, gravityPosition)!;
    final speed = fallT;
    final stretch = 1.0 + speed * 0.9;
    // 体积守恒：拉伸时头圆变小、锥尾变长。
    final radius = baseRadius / math.sqrt(stretch);
    final tailLength = baseRadius * (0.9 + (stretch - 1.0) * 2.4);
    // 撞击摊开：落地瞬间沿水平方向压扁扩散。
    final squashT =
        ((phase - impactStart) / (mergeEnd - impactStart)).clamp(0.0, 1.0);
    final spread = phase >= impactStart
        ? 1.0 + math.sin(squashT * math.pi) * 0.5
        : 1.0;

    // 液桥：脱离阶段连接源点，合并阶段连接液面。
    Offset? bridgeAnchor;
    double bridgeStrength = 0;
    if (phase < detachEnd) {
      bridgeAnchor = source;
      bridgeStrength = 1.0 - phase / detachEnd;
    } else if (phase > 0.60 &&
        phase < mergeEnd &&
        (target - center).distance <= baseRadius * 3.2) {
      bridgeAnchor = target;
      bridgeStrength = math.sin(
          ((phase - 0.60) / (mergeEnd - 0.60)) * math.pi);
    }
    if (bridgeAnchor != null && bridgeStrength > 0.02) {
      _paintLiquidBridge(canvas, center, bridgeAnchor, baseRadius,
          bridgeStrength, liquidPaint);
    }

    if (phase < mergeEnd) {
      _drawTeardrop(canvas, center, radius, tailLength, spread, liquidPaint);
    }

    // 撞击水花：横向的液面是竖直前沿、竖向是水平液面，水花都向上溅起。
    if (phase >= impactStart && phase < mergeEnd) {
      final p = ((phase - impactStart) / (mergeEnd - impactStart))
          .clamp(0.0, 1.0);
      final splashPaint = Paint()
        ..color = _colors.last.withValues(alpha: (1 - p) * 0.38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round;
      final spreadAmt = baseRadius * (0.8 + p * 1.8);
      if (orientation == Axis.horizontal) {
        canvas.drawArc(
          Rect.fromCenter(
              center: target, width: spreadAmt, height: spreadAmt * 1.5),
          -math.pi / 2,
          math.pi,
          false,
          splashPaint,
        );
      } else {
        canvas.drawArc(
          Rect.fromCenter(
              center: target, width: spreadAmt * 1.8, height: spreadAmt),
          -math.pi,
          math.pi,
          false,
          splashPaint,
        );
      }
    }
  }

  /// 物理水滴形状：圆头（下落方向）+ 锥形尾部，垂直下落。
  /// 撞击时沿水平方向整体摊开（spread > 1）。
  void _drawTeardrop(
    Canvas canvas,
    Offset center,
    double radius,
    double tailLength,
    double spread,
    Paint paint,
  ) {
    final head = Offset(center.dx, center.dy + (tailLength - radius) / 2.0);
    final tip = Offset(center.dx, center.dy - (tailLength + radius) / 2.0);

    if (spread > 1.01) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(spread, 1.0);
      canvas.translate(-center.dx, -center.dy);
    }

    // 头部圆
    canvas.drawOval(
      Rect.fromCenter(center: head, width: radius * 2, height: radius * 2),
      paint,
    );

    // 锥形尾部：从头圆两个切线点收敛到尖端。
    final L = (tip - head).distance;
    if (L > radius * 1.001) {
      final cosA = radius / L;
      final sinA = math.sqrt(1.0 - cosA * cosA);
      final p1 = Offset(head.dx + radius * sinA, head.dy - radius * cosA);
      final p2 = Offset(head.dx - radius * sinA, head.dy - radius * cosA);
      final q1 = tip + (p1 - tip) * 0.5;
      final q2 = tip + (p2 - tip) * 0.5;
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..quadraticBezierTo(q1.dx, q1.dy, tip.dx, tip.dy)
        ..quadraticBezierTo(q2.dx, q2.dy, p2.dx, p2.dy)
        ..close();
      canvas.drawPath(path, paint);
    }

    if (spread > 1.01) {
      canvas.restore();
    }

    // 高光
    canvas.drawCircle(
      Offset(head.dx + radius * 0.32, head.dy - radius * 0.30),
      radius * 0.22,
      Paint()..color = Colors.white.withValues(alpha: 0.26),
    );
  }

  void _paintLiquidBridge(
    Canvas canvas,
    Offset drop,
    Offset anchor,
    double radius,
    double strength,
    Paint paint,
  ) {
    final delta = anchor - drop;
    final distance = delta.distance;
    if (distance < 0.01) return;
    final direction = delta / distance;
    final normal = Offset(-direction.dy, direction.dx);
    final half = radius * (0.18 + strength * 0.38);
    final startA = drop + normal * half;
    final startB = drop - normal * half;
    final endA = anchor + normal * half * 0.45;
    final endB = anchor - normal * half * 0.45;
    final path = Path()
      ..moveTo(startA.dx, startA.dy)
      ..cubicTo(
        drop.dx + delta.dx * 0.36 + normal.dx * half,
        drop.dy + delta.dy * 0.36 + normal.dy * half,
        anchor.dx - delta.dx * 0.18 + normal.dx * half * 0.45,
        anchor.dy - delta.dy * 0.18 + normal.dy * half * 0.45,
        endA.dx,
        endA.dy,
      )
      ..lineTo(endB.dx, endB.dy)
      ..cubicTo(
        anchor.dx - delta.dx * 0.18 - normal.dx * half * 0.45,
        anchor.dy - delta.dy * 0.18 - normal.dy * half * 0.45,
        drop.dx + delta.dx * 0.36 - normal.dx * half,
        drop.dy + delta.dy * 0.36 - normal.dy * half,
        startB.dx,
        startB.dy,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  // ----------------------------------------------------------------
  // 马赛克：按格子填充 + 波纹扫过已填充区域
  // ----------------------------------------------------------------
  void _paintMosaic(Canvas canvas, Rect rect) {
    const cell = 7.0;
    final cols = math.max(1, (rect.width / cell).floor());
    final rows = math.max(1, (rect.height / cell).floor());
    final total = cols * rows;
    final full = (value.clamp(0.0, 1.0) * total).floor();
    final frac = value.clamp(0.0, 1.0) * total - full;

    final g0 = _colors.first;
    final g1 = _colors.last;
    final t = animations ? time : 0.0;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final order = orientation == Axis.horizontal
            ? r * cols + c
            : (rows - 1 - r) * cols + c;
        double alpha;
        if (order < full) {
          alpha = 1.0;
        } else if (order == full && frac > 0) {
          alpha = frac;
        } else {
          continue;
        }
        // 位置渐变 + 波动扫光
        final gPos = orientation == Axis.horizontal
            ? (cols <= 1 ? 0.0 : c / (cols - 1))
            : (rows <= 1 ? 0.0 : (rows - 1 - r) / (rows - 1));
        var color = Color.lerp(g0, g1, gPos)!;
        if (animations) {
          final wave = 0.5 + 0.5 * math.sin(2 * math.pi * (t * 1.5 - order * 0.07));
          color = Color.lerp(color, Colors.white, 0.22 * wave)!;
        }
        final cellRect = Rect.fromLTWH(
          rect.left + c * cell + 1,
          rect.top + r * cell + 1,
          cell - 2,
          cell - 2,
        );
        canvas.drawRect(
          cellRect,
          Paint()..color = color.withValues(alpha: alpha),
        );
      }
    }
  }

  // ----------------------------------------------------------------
  // 条纹：填充区内的斜纹随时间流动
  // ----------------------------------------------------------------
  void _paintStriped(Canvas canvas, Rect rect, double radius) {
    final fill = _fillRect(rect);
    if (fill.width <= 0 || fill.height <= 0) return;
    final rrect = RRect.fromRectAndRadius(fill, Radius.circular(radius));
    canvas.drawRRect(rrect, _gradientPaint(fill));

    final stripe = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 5.0;
    final t = animations ? time : 0.0;
    final off = (t * 16.0) % 11.0; // 条纹流动偏移
    _clipFill(canvas, rect, () {
      if (orientation == Axis.horizontal) {
        for (var x = rect.left - rect.height; x < rect.right; x += 11.0) {
          final sx = x + off;
          canvas.drawLine(
            Offset(sx, rect.top),
            Offset(sx + rect.height, rect.bottom),
            stripe,
          );
        }
      } else {
        for (var y = rect.top - rect.width; y < rect.bottom; y += 11.0) {
          final sy = y + off;
          canvas.drawLine(
            Offset(rect.left, sy),
            Offset(rect.right, sy + rect.width),
            stripe,
          );
        }
      }
    });
  }

  // ----------------------------------------------------------------
  // 发光：模糊光晕 + 呼吸脉冲 + 移动光带
  // ----------------------------------------------------------------
  void _paintGlow(Canvas canvas, Rect rect, double radius) {
    final fill = _fillRect(rect);
    if (fill.width <= 0 || fill.height <= 0) return;

    final pulse = animations ? 0.65 + 0.35 * math.sin(2 * math.pi * time) : 1.0;

    // 光晕（模糊层）
    final haloPaint = Paint()
      ..color = _colors.last.withValues(alpha: 0.30 * pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fill.inflate(4), Radius.circular(radius)),
      haloPaint,
    );

    // 实心填充
    final rrect = RRect.fromRectAndRadius(fill, Radius.circular(radius));
    canvas.drawRRect(rrect, _gradientPaint(fill));

    // 移动光带
    if (animations) {
      _clipFill(canvas, rect, () {
        final t = time;
        if (orientation == Axis.horizontal) {
          final bx = fill.left + ((t * 2.0) % 1.0) * fill.width * 1.2 - fill.width * 0.2;
          final bandRect = Rect.fromLTWH(
              bx, fill.top, fill.width * 0.22, fill.height);
          canvas.drawRect(
            bandRect,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ).createShader(bandRect),
          );
        } else {
          final by = fill.top + ((t * 2.0) % 1.0) * fill.height * 1.2 - fill.height * 0.2;
          final bandRect =
              Rect.fromLTWH(fill.left, by, fill.width, fill.height * 0.22);
          canvas.drawRect(
            bandRect,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ).createShader(bandRect),
          );
        }
      });
    }
  }

  // ----------------------------------------------------------------
  // 波纹：多重正弦波叠加的波动前沿（类似怪猎荒野生命条）
  // ----------------------------------------------------------------
  void _paintWave(Canvas canvas, Rect rect, double radius) {
    final v = value.clamp(0.0, 1.0);
    if (v <= 0) return;
    final fill = _fillRect(rect);
    final t = animations ? time : 0.0;
    final perp = orientation == Axis.horizontal ? rect.height : rect.width;
    const seg = 24;

    // 波幅函数：sin(pi*pos) 包络把两端锚定在液面角点，
    // 内部叠加三个不同频率 / 相位 / 方向的正弦波，随时间流动。
    double wave(double pos, double phase) {
      final envelope = math.sin(math.pi * pos);
      final w = 0.07 * math.sin(2 * math.pi * (2.0 * pos + phase)) +
          0.05 * math.sin(2 * math.pi * (3.7 * pos - phase * 1.6)) +
          0.03 * math.sin(2 * math.pi * (8.3 * pos + phase * 0.7));
      return envelope * w * perp;
    }

    final path = Path();
    if (orientation == Axis.horizontal) {
      path
        ..moveTo(rect.left, rect.top)
        ..lineTo(fill.right, rect.top);
      for (var i = 0; i <= seg; i++) {
        final p = i / seg;
        path.lineTo(fill.right + wave(p, t), rect.top + rect.height * p);
      }
      path
        ..lineTo(fill.right, rect.bottom)
        ..lineTo(rect.left, rect.bottom);
    } else {
      path
        ..moveTo(rect.left, rect.bottom)
        ..lineTo(rect.left, fill.top);
      for (var i = 0; i <= seg; i++) {
        final p = i / seg;
        path.lineTo(rect.left + rect.width * p, fill.top + wave(p, t));
      }
      path
        ..lineTo(rect.right, fill.top)
        ..lineTo(rect.right, rect.bottom);
    }
    path.close();

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    canvas.drawPath(path, _gradientPaint(rect));

    // 前沿亮边：能量感
    final edge = Path();
    if (orientation == Axis.horizontal) {
      edge.moveTo(fill.right, rect.top);
      for (var i = 0; i <= seg; i++) {
        final p = i / seg;
        edge.lineTo(fill.right + wave(p, t), rect.top + rect.height * p);
      }
    } else {
      edge.moveTo(rect.left, fill.top);
      for (var i = 0; i <= seg; i++) {
        final p = i / seg;
        edge.lineTo(rect.left + rect.width * p, fill.top + wave(p, t));
      }
    }
    canvas.drawPath(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.22),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) {
    return old.value != value ||
        old.orientation != orientation ||
        old.theme != theme ||
        old.style != style ||
        old.isMain != isMain ||
        old.animations != animations ||
        old.time != time;
  }
}
