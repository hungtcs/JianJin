import 'package:flutter/widgets.dart';

import '../../models/segment.dart';
import '../theme.dart';
import 'timeline_view_controller.dart';

/// 全局条：永远显示整片，是「地图」。
///
/// 三个职责：标了哪些、整体内容分布、下面那条正在看哪一段。
/// **刻意不画播放头竖线**——它和下方细节轨的竖线处在不同缩放下，
/// 永远对不齐，反而误导。播放位置改用底边的小三角标示。
class OverviewBar extends StatefulWidget {
  const OverviewBar({
    super.key,
    required this.view,
    required this.position,
    required this.segments,
    required this.waveform,
    this.selectedId,
  });

  final TimelineViewController view;
  final Duration position;
  final List<Segment> segments;
  final List<double> waveform;
  final String? selectedId;

  @override
  State<OverviewBar> createState() => _OverviewBarState();
}

enum _Drag { none, viewport, resizeLeft, resizeRight }

/// 视口框的最小宽度。**绘制与命中共用同一个值**——
/// 若命中区比看到的框宽，用户抓可见边缘时抓到的却是中段（平移），
/// 所见即所得就被破坏了。放大到时间范围极小时框会趋近于零宽，
/// 靠这个下限保证两条边始终看得见也抓得住。
const double kMinViewportW = 24.0;

class _OverviewBarState extends State<OverviewBar> {
  _Drag _drag = _Drag.none;
  bool _overViewport = false;

  /// 按下时指针相对视口左沿的偏移，避免视口跳到指针位置
  double _grabDx = 0;

  /// hover 命中的是视口的哪个部分
  _Drag _hoverPart = _Drag.none;

  /// 视口边缘的命中宽度
  static const _edgeHitPx = 5.0;

  TimelineViewController get _v => widget.view;

  double _totalMs() => _v.duration.inMilliseconds.toDouble();

  (double, double) _viewportRect(double w) => viewportRectOf(_v, w);

  /// 命中优先级：视口左右边缘 > 视口主体 > 空白
  _Drag _partAt(double x, double w) {
    if (_v.fitsEntirely) return _Drag.none;
    final (hx, hw) = _viewportRect(w);

    // 边缘命中区可以向框外延伸，这样窄框也留得下中间的拖动区
    final edge = hw / 3 < _edgeHitPx ? hw / 3 : _edgeHitPx;
    if (x >= hx - _edgeHitPx && x <= hx + edge) return _Drag.resizeLeft;
    if (x >= hx + hw - edge && x <= hx + hw + _edgeHitPx) {
      return _Drag.resizeRight;
    }
    if (x > hx && x < hx + hw) return _Drag.viewport;
    return _Drag.none;
  }

  double _msAt(double x, double w) {
    final total = _totalMs();
    if (w <= 0) return 0;
    return (x / w).clamp(0.0, 1.0) * total;
  }

  void _panViewportTo(double dx, double w) {
    final total = _totalMs();
    if (total <= 0 || w <= 0) return;
    final (_, vw) = _viewportRect(w);
    final left = (dx - _grabDx).clamp(0.0, w - vw);
    _v.panToStart(left / w * total);
  }

  void _onDown(PointerDownEvent e, double w) {
    final x = e.localPosition.dx;
    final part = _partAt(x, w);

    if (part == _Drag.resizeLeft || part == _Drag.resizeRight) {
      setState(() => _drag = part);
      return;
    }
    if (part == _Drag.viewport) {
      final (vx, _) = _viewportRect(w);
      _grabDx = x - vx;
      setState(() => _drag = _Drag.viewport);
      return;
    }

    // 空白处按下：视口居中到指针，并继续跟着拖。
    // 不改播放进度——全片条只负责「看哪一段」。
    if (_v.fitsEntirely) return;
    final (_, vw) = _viewportRect(w);
    _grabDx = vw / 2;
    setState(() => _drag = _Drag.viewport);
    _panViewportTo(x, w);
  }

  void _onMove(PointerMoveEvent e, double w) {
    final x = e.localPosition.dx;
    switch (_drag) {
      case _Drag.viewport:
        _panViewportTo(x, w);
      case _Drag.resizeLeft:
        // 拖左沿：右沿钉住不动，视野随之缩放
        _v.setViewRange(_msAt(x, w), _v.viewEndMs);
      case _Drag.resizeRight:
        _v.setViewRange(_v.viewStartMs, _msAt(x, w));
      case _Drag.none:
        break;
    }
  }

  MouseCursor get _cursor {
    final active = _drag != _Drag.none ? _drag : _hoverPart;
    return switch (active) {
      _Drag.resizeLeft ||
      _Drag.resizeRight =>
        SystemMouseCursors.resizeLeftRight,
      _Drag.viewport => _drag == _Drag.viewport
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab,
      _Drag.none => SystemMouseCursors.precise,
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return MouseRegion(
          cursor: _cursor,
          onHover: (e) {
            final part = _partAt(e.localPosition.dx, w);
            final over = part != _Drag.none;
            if (part != _hoverPart || over != _overViewport) {
              setState(() {
                _hoverPart = part;
                _overViewport = over;
              });
            }
          },
          onExit: (_) {
            if (_overViewport || _hoverPart != _Drag.none) {
              setState(() {
                _overViewport = false;
                _hoverPart = _Drag.none;
              });
            }
          },
          child: Listener(
            onPointerDown: (e) => _onDown(e, w),
            onPointerMove: (e) => _onMove(e, w),
            onPointerUp: (_) => setState(() => _drag = _Drag.none),
            child: CustomPaint(
              size: Size(w, AppMetrics.overviewHeight),
              painter: _OverviewPainter(
                view: _v,
                position: widget.position,
                segments: widget.segments,
                waveform: widget.waveform,
                selectedId: widget.selectedId,
                hoverViewport: _overViewport || _drag == _Drag.viewport,
                repaint: _v,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 视口框在全局条上的像素范围，绘制与命中判定共用。
(double, double) viewportRectOf(TimelineViewController v, double w) {
  final total = v.duration.inMilliseconds.toDouble();
  if (total <= 0 || w <= 0) return (0, w);
  final x1 = (v.viewStartMs / total).clamp(0.0, 1.0) * w;
  final x2 = (v.viewEndMs / total).clamp(0.0, 1.0) * w;
  final width = (x2 - x1) < kMinViewportW ? kMinViewportW : (x2 - x1);
  return (x1.clamp(0.0, (w - width).clamp(0.0, w)), width);
}

class _OverviewPainter extends CustomPainter {
  _OverviewPainter({
    required this.view,
    required this.position,
    required this.segments,
    required this.waveform,
    required this.selectedId,
    required this.hoverViewport,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final TimelineViewController view;
  final Duration position;
  final List<Segment> segments;
  final List<double> waveform;
  final String? selectedId;
  final bool hoverViewport;

  double _x(Duration t, double w) {
    final total = view.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (t.inMilliseconds / total).clamp(0.0, 1.0) * w;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.panelAlt);

    // 波形作为低对比度背景纹理：能一眼看出哪里是静音，
    // 但对比度压得足够低，不会被误读成一条独立音轨
    if (waveform.isNotEmpty && w > 0) {
      final paint = Paint()..color = AppColors.waveform.withValues(alpha: 0.30);
      final mid = h / 2;
      final step = waveform.length / w;
      for (var px = 0; px < w.floor(); px++) {
        final i = (px * step).floor().clamp(0, waveform.length - 1);
        final amp = waveform[i] * (h * 0.40);
        if (amp < 0.3) continue;
        canvas.drawLine(
          Offset(px + 0.5, mid - amp),
          Offset(px + 0.5, mid + amp),
          paint,
        );
      }
    }

    // 片段块
    final segFill = Paint()..color = AppColors.segment.withValues(alpha: 0.8);
    final segSel = Paint()..color = AppColors.segmentSelected;
    for (final s in segments) {
      final x1 = _x(s.start, w);
      final x2 = _x(s.end, w);
      canvas.drawRRect(
        RRect.fromLTRBR(
          x1,
          h * 0.18,
          x2 < x1 + 2 ? x1 + 2 : x2,
          h * 0.82,
          const Radius.circular(2),
        ),
        s.id == selectedId ? segSel : segFill,
      );
    }

    // 视口框：可拖拽，hover 时加亮以明示
    if (!view.fitsEntirely) {
      final total = view.duration.inMilliseconds.toDouble();
      if (total > 0) {
        final (vx, vw) = viewportRectOf(view, w);

        canvas.drawRect(
          Rect.fromLTWH(vx, 0, vw, h),
          Paint()
            ..color =
                AppColors.accent.withValues(alpha: hoverViewport ? 0.26 : 0.15),
        );
        canvas.drawRect(
          Rect.fromLTWH(vx + 0.75, 0.75, vw - 1.5, h - 1.5),
          Paint()
            ..color =
                AppColors.accent.withValues(alpha: hoverViewport ? 1.0 : 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );

        // 两侧握把，明示这是个可拖的东西
        if (hoverViewport && vw > 14) {
          final grip = Paint()..color = AppColors.accent;
          for (final gx in [vx + 3.5, vx + vw - 3.5]) {
            canvas.drawLine(
              Offset(gx, h * 0.3),
              Offset(gx, h * 0.7),
              grip..strokeWidth = 1.5,
            );
          }
        }
      }
    }

    // 播放位置：顶边向下的三角，形状与细节轨的播放头一致。
    // 只作展示，不可点击——全片条整体都用于拖视口，
    // 再让某个点做别的事只会制造歧义。
    // 之前这里是底边向上的三角，和下方的向下三角首尾相对，
    // 看起来像两个不同优先级的东西，实际它们是同一个概念。
    // 仍然不画竖线：两轨缩放不同，竖线永远对不齐（见类注释）。
    final px = _x(position, w);
    final marker = Path()
      ..moveTo(px - 5, 0)
      ..lineTo(px + 5, 0)
      ..lineTo(px, 7)
      ..close();
    canvas.drawPath(marker, Paint()..color = AppColors.playhead);
  }

  @override
  bool shouldRepaint(_OverviewPainter old) =>
      old.position != position ||
      old.segments != segments ||
      old.waveform != waveform ||
      old.selectedId != selectedId ||
      old.hoverViewport != hoverViewport;
}
