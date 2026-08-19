import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 全部图标自绘。不用 Material 图标字体，也就不必 uses-material-design: true。
/// 视频工具的图标本来就是简单几何形，手绘反而更锐利可控。
enum AppIcon {
  play,
  pause,
  markIn,
  markOut,
  retro,
  delete,
  export,
  folder,
  undo,
  chevronLeft,
  chevronRight,
}

class Icon extends StatelessWidget {
  const Icon(this.icon, {super.key, this.size = 16, this.color});

  final AppIcon icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _IconPainter(
          icon,
          color ?? const Color(0xFFD8D8DB),
        ),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color);

  final AppIcon icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.25, w * 0.1)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    switch (icon) {
      case AppIcon.play:
        final path = Path()
          ..moveTo(w * 0.26, h * 0.16)
          ..lineTo(w * 0.82, h * 0.5)
          ..lineTo(w * 0.26, h * 0.84)
          ..close();
        canvas.drawPath(path, fill);

      case AppIcon.pause:
        final bw = w * 0.19;
        canvas.drawRRect(
          RRect.fromLTRBR(w * 0.26, h * 0.17, w * 0.26 + bw, h * 0.83,
              Radius.circular(bw * 0.28)),
          fill,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(w * 0.55, h * 0.17, w * 0.55 + bw, h * 0.83,
              Radius.circular(bw * 0.28)),
          fill,
        );

      // 入点：左侧竖条 + 向右的实心三角，语义是「从这里开始」
      case AppIcon.markIn:
        canvas.drawRect(
            Rect.fromLTRB(w * 0.2, h * 0.16, w * 0.32, h * 0.84), fill);
        final tri = Path()
          ..moveTo(w * 0.42, h * 0.22)
          ..lineTo(w * 0.82, h * 0.5)
          ..lineTo(w * 0.42, h * 0.78)
          ..close();
        canvas.drawPath(tri, fill);

      // 出点：右侧竖条 + 向左的实心三角
      case AppIcon.markOut:
        canvas.drawRect(
            Rect.fromLTRB(w * 0.68, h * 0.16, w * 0.8, h * 0.84), fill);
        final tri = Path()
          ..moveTo(w * 0.58, h * 0.22)
          ..lineTo(w * 0.18, h * 0.5)
          ..lineTo(w * 0.58, h * 0.78)
          ..close();
        canvas.drawPath(tri, fill);

      // 追溯：逆时针箭头，表示「回头补一段」
      case AppIcon.retro:
        final r = w * 0.3;
        final c = Offset(w * 0.5, h * 0.54);
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          math.pi * 0.85,
          math.pi * 1.35,
          false,
          stroke,
        );
        final head = Path()
          ..moveTo(c.dx - r * 1.05, c.dy - r * 0.42)
          ..lineTo(c.dx - r * 0.28, c.dy - r * 0.62)
          ..lineTo(c.dx - r * 0.72, c.dy + r * 0.16)
          ..close();
        canvas.drawPath(head, fill);

      case AppIcon.delete:
        canvas.drawLine(
            Offset(w * 0.26, h * 0.26), Offset(w * 0.74, h * 0.74), stroke);
        canvas.drawLine(
            Offset(w * 0.74, h * 0.26), Offset(w * 0.26, h * 0.74), stroke);

      case AppIcon.export:
        canvas.drawLine(
            Offset(w * 0.5, h * 0.62), Offset(w * 0.5, h * 0.14), stroke);
        final head = Path()
          ..moveTo(w * 0.32, h * 0.32)
          ..lineTo(w * 0.5, h * 0.12)
          ..lineTo(w * 0.68, h * 0.32);
        canvas.drawPath(head, stroke);
        final tray = Path()
          ..moveTo(w * 0.2, h * 0.62)
          ..lineTo(w * 0.2, h * 0.84)
          ..lineTo(w * 0.8, h * 0.84)
          ..lineTo(w * 0.8, h * 0.62);
        canvas.drawPath(tray, stroke);

      case AppIcon.folder:
        final path = Path()
          ..moveTo(w * 0.14, h * 0.76)
          ..lineTo(w * 0.14, h * 0.26)
          ..lineTo(w * 0.42, h * 0.26)
          ..lineTo(w * 0.52, h * 0.38)
          ..lineTo(w * 0.86, h * 0.38)
          ..lineTo(w * 0.86, h * 0.76)
          ..close();
        canvas.drawPath(path, stroke);

      case AppIcon.undo:
        final r = w * 0.28;
        final c = Offset(w * 0.52, h * 0.56);
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          math.pi * 0.9,
          math.pi * 1.3,
          false,
          stroke,
        );
        final head = Path()
          ..moveTo(c.dx - r * 1.1, c.dy - r * 0.35)
          ..lineTo(c.dx - r * 0.3, c.dy - r * 0.6)
          ..lineTo(c.dx - r * 0.75, c.dy + r * 0.25)
          ..close();
        canvas.drawPath(head, fill);

      case AppIcon.chevronLeft:
        final path = Path()
          ..moveTo(w * 0.62, h * 0.22)
          ..lineTo(w * 0.36, h * 0.5)
          ..lineTo(w * 0.62, h * 0.78);
        canvas.drawPath(path, stroke);

      case AppIcon.chevronRight:
        final path = Path()
          ..moveTo(w * 0.38, h * 0.22)
          ..lineTo(w * 0.64, h * 0.5)
          ..lineTo(w * 0.38, h * 0.78);
        canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color;
}
