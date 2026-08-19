import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../models/segment.dart';
import '../theme.dart';
import 'thumbnail_cache.dart';
import 'timeline_view_controller.dart';

/// 细节轨的分带高度。**state 的命中测试与 painter 的绘制必须共用这一份**——
/// 曾经命中测试只看横坐标，导致刻度尺区域虽然没画片段却能拖动片段。
class TimelineBands {
  const TimelineBands._();

  /// 刻度尺 + 关键帧刻度；此带只做 scrub，不参与片段交互
  static const ruler = 18.0;
  static const thumbTop = 18.0;
  static const thumbH = 46.0;
  static const waveTop = 64.0;
}

/// 细节时间轴：可缩放，画缩略图、波形、关键帧刻度、片段。
///
/// 分带布局（总高 [AppMetrics.detailHeight]）：
///   0..18   刻度尺 + 关键帧刻度
///   18..64  缩略图条
///   64..96  波形
class DetailTimeline extends StatefulWidget {
  const DetailTimeline({
    super.key,
    required this.view,
    required this.position,
    required this.segments,
    required this.keyframes,
    required this.waveform,
    required this.thumbnails,
    required this.cache,
    this.thumbnailsLoading = false,
    this.waveformLoading = false,
    required this.onScrubStart,
    required this.onScrub,
    required this.onScrubEnd,
    required this.onSelect,
    required this.onResize,
    this.selectedId,
    this.pendingIn,
  });

  final TimelineViewController view;
  final Duration position;
  final List<Segment> segments;
  final List<Duration> keyframes;
  final List<double> waveform;
  final List<String> thumbnails;
  final ThumbnailCache cache;
  final bool thumbnailsLoading;
  final bool waveformLoading;

  final VoidCallback onScrubStart;
  final ValueChanged<Duration> onScrub;
  final ValueChanged<Duration> onScrubEnd;
  final ValueChanged<String?> onSelect;

  /// (id, start, end, commit)
  final void Function(String id, Duration? start, Duration? end, bool commit)
      onResize;

  final String? selectedId;
  final Duration? pendingIn;

  @override
  State<DetailTimeline> createState() => _DetailTimelineState();
}

enum _DragMode { none, scrub, resizeStart, resizeEnd, moveSegment }

/// 指针下方是什么，决定光标形状。
/// 「按下去才知道能拖」是很差的体验，hover 就该给出反馈。
enum _HoverTarget { empty, edge, body }

class _DetailTimelineState extends State<DetailTimeline> {
  _DragMode _mode = _DragMode.none;
  String? _dragId;

  /// 拖动片段主体时，指针相对片段起点的偏移，避免片段跳到指针位置
  Duration _grabOffset = Duration.zero;
  Duration _grabDuration = Duration.zero;

  _HoverTarget _hover = _HoverTarget.empty;

  static const _edgeHitPx = 6.0;

  TimelineViewController get _v => widget.view;

  _HoverTarget _targetAt(double x, double y) {
    // 刻度尺带不画片段，就不该能拖片段——交互区必须和可见区一致
    if (y < TimelineBands.ruler) return _HoverTarget.empty;

    for (final s in widget.segments) {
      final xs = _v.xOf(s.start);
      final xe = _v.xOf(s.end);
      if ((x - xs).abs() <= _edgeHitPx || (x - xe).abs() <= _edgeHitPx) {
        return _HoverTarget.edge;
      }
    }
    final t = _v.timeAt(x);
    for (final s in widget.segments) {
      if (s.contains(t)) return _HoverTarget.body;
    }
    return _HoverTarget.empty;
  }

  void _onHover(PointerHoverEvent e) {
    if (_mode != _DragMode.none) return;
    final t = _targetAt(e.localPosition.dx, e.localPosition.dy);
    if (t != _hover) setState(() => _hover = t);
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed) {
      _v.zoomAt(e.scrollDelta.dy > 0 ? 0.88 : 1.14, e.localPosition.dx);
    } else {
      // 普通滚轮只有 dy，横向时间轴上按 dy 平移才符合直觉
      final d = e.scrollDelta.dx != 0 ? e.scrollDelta.dx : e.scrollDelta.dy;
      _v.panByPixels(d);
    }
  }

  double _panZoomStartPx = 0;

  void _onPanZoomStart(PointerPanZoomStartEvent e) =>
      _panZoomStartPx = _v.pxPerMs;

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    // 触控板：双指捏合缩放，双指平移滚动
    if ((e.scale - 1.0).abs() > 0.001) {
      _v.zoomTo(_panZoomStartPx * e.scale, e.localPosition.dx);
    } else {
      _v.panByPixels(-e.panDelta.dx);
    }
  }

  /// 命中优先级：片段边缘 > 片段主体 > 空白（scrub）
  void _onDown(PointerDownEvent e) {
    final x = e.localPosition.dx;
    final y = e.localPosition.dy;

    // 刻度尺带只做 scrub。放在最前面，保证它永远不会落进片段拖动分支。
    if (y < TimelineBands.ruler) {
      widget.onSelect(null);
      setState(() => _mode = _DragMode.scrub);
      widget.onScrubStart();
      widget.onScrub(_v.timeAt(x));
      return;
    }

    for (final s in widget.segments) {
      final xs = _v.xOf(s.start);
      final xe = _v.xOf(s.end);
      if ((x - xs).abs() <= _edgeHitPx) {
        widget.onSelect(s.id);
        setState(() {
          _mode = _DragMode.resizeStart;
          _dragId = s.id;
        });
        return;
      }
      if ((x - xe).abs() <= _edgeHitPx) {
        widget.onSelect(s.id);
        setState(() {
          _mode = _DragMode.resizeEnd;
          _dragId = s.id;
        });
        return;
      }
    }

    final t = _v.timeAt(x);

    // 片段主体：整体平移，时长保持不变
    for (final s in widget.segments) {
      if (s.contains(t)) {
        widget.onSelect(s.id);
        setState(() {
          _mode = _DragMode.moveSegment;
          _dragId = s.id;
          _grabOffset = t - s.start;
          _grabDuration = s.duration;
        });
        return;
      }
    }

    widget.onSelect(null);
    setState(() => _mode = _DragMode.scrub);
    widget.onScrubStart();
    widget.onScrub(t);
  }

  void _applyMove(Duration pointer, bool commit) {
    if (_dragId == null) return;
    var start = pointer - _grabOffset;
    if (start < Duration.zero) start = Duration.zero;
    var end = start + _grabDuration;
    final total = _v.duration;
    if (total > Duration.zero && end > total) {
      end = total;
      start = end - _grabDuration;
      if (start < Duration.zero) start = Duration.zero;
    }
    widget.onResize(_dragId!, start, end, commit);
  }

  void _onMove(PointerMoveEvent e) {
    if (_mode == _DragMode.none) return;
    final t = _v.timeAt(e.localPosition.dx);

    switch (_mode) {
      case _DragMode.scrub:
        widget.onScrub(t);
      case _DragMode.resizeStart:
        if (_dragId != null) widget.onResize(_dragId!, t, null, false);
      case _DragMode.resizeEnd:
        if (_dragId != null) widget.onResize(_dragId!, null, t, false);
      case _DragMode.moveSegment:
        _applyMove(t, false);
      case _DragMode.none:
        break;
    }
  }

  void _onUp(PointerUpEvent e) {
    final t = _v.timeAt(e.localPosition.dx);
    switch (_mode) {
      case _DragMode.scrub:
        widget.onScrubEnd(t);
      case _DragMode.resizeStart:
        if (_dragId != null) widget.onResize(_dragId!, t, null, true);
      case _DragMode.resizeEnd:
        if (_dragId != null) widget.onResize(_dragId!, null, t, true);
      case _DragMode.moveSegment:
        _applyMove(t, true);
      case _DragMode.none:
        break;
    }
    setState(() {
      _mode = _DragMode.none;
      _dragId = null;
    });
  }

  MouseCursor get _cursor {
    switch (_mode) {
      case _DragMode.resizeStart:
      case _DragMode.resizeEnd:
        return SystemMouseCursors.resizeLeftRight;
      case _DragMode.moveSegment:
        return SystemMouseCursors.grabbing;
      case _DragMode.scrub:
        return SystemMouseCursors.precise;
      case _DragMode.none:
        return switch (_hover) {
          _HoverTarget.edge => SystemMouseCursors.resizeLeftRight,
          _HoverTarget.body => SystemMouseCursors.grab,
          _HoverTarget.empty => SystemMouseCursors.precise,
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _v.setWidth(c.maxWidth);
        });

        return MouseRegion(
          cursor: _cursor,
          onHover: _onHover,
          onExit: (_) {
            if (_hover != _HoverTarget.empty) {
              setState(() => _hover = _HoverTarget.empty);
            }
          },
          child: Listener(
            onPointerSignal: _onSignal,
            onPointerPanZoomStart: _onPanZoomStart,
            onPointerPanZoomUpdate: _onPanZoomUpdate,
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            child: ClipRect(
              child: CustomPaint(
                size: Size(c.maxWidth, AppMetrics.detailHeight),
                painter: _DetailPainter(
                  view: _v,
                  position: widget.position,
                  segments: widget.segments,
                  keyframes: widget.keyframes,
                  waveform: widget.waveform,
                  thumbnails: widget.thumbnails,
                  cache: widget.cache,
                  thumbnailsLoading: widget.thumbnailsLoading,
                  waveformLoading: widget.waveformLoading,
                  selectedId: widget.selectedId,
                  pendingIn: widget.pendingIn,
                  repaint: Listenable.merge([widget.cache, _v]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DetailPainter extends CustomPainter {
  _DetailPainter({
    required this.view,
    required this.position,
    required this.segments,
    required this.keyframes,
    required this.waveform,
    required this.thumbnails,
    required this.cache,
    required this.thumbnailsLoading,
    required this.waveformLoading,
    required this.selectedId,
    required this.pendingIn,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final TimelineViewController view;
  final Duration position;
  final List<Segment> segments;
  final List<Duration> keyframes;
  final List<double> waveform;
  final List<String> thumbnails;
  final ThumbnailCache cache;
  final bool thumbnailsLoading;
  final bool waveformLoading;
  final String? selectedId;
  final Duration? pendingIn;

  static const _rulerH = TimelineBands.ruler;
  static const _thumbTop = TimelineBands.thumbTop;
  static const _thumbH = TimelineBands.thumbH;
  static const _waveTop = TimelineBands.waveTop;

  double get _viewStartMs => view.viewStartMs;
  double get _pxPerMs => view.pxPerMs;
  Duration get _duration => view.duration;

  double _x(num ms) => (ms - _viewStartMs) * _pxPerMs;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final viewEndMs = _viewStartMs + w / _pxPerMs;

    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.bg);

    _paintThumbnails(canvas, w);
    _paintWaveform(canvas, w, h);
    _paintRuler(canvas, w, viewEndMs);
    _paintKeyframes(canvas, viewEndMs);
    _paintSegments(canvas, w, h);
    _paintPending(canvas, h);
    _paintPlayhead(canvas, h);
  }

  /// 在某一带里居中写一行状态文字。
  /// 缩略图和波形都要 ffmpeg 扫完整个文件才出得来，长视频要等一会儿，
  /// 空着不给反馈会让人以为坏了。
  void _bandNotice(Canvas canvas, double w, double top, double h, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: AppText.label.copyWith(
          fontSize: 10.5,
          color: AppColors.textFaint,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((w - tp.width) / 2, top + (h - tp.height) / 2),
    );
  }

  void _paintThumbnails(Canvas canvas, double w) {
    canvas.drawRect(
      Rect.fromLTWH(0, _thumbTop, w, _thumbH),
      Paint()..color = AppColors.panel,
    );
    if (thumbnails.isEmpty && thumbnailsLoading) {
      _bandNotice(canvas, w, _thumbTop, _thumbH, '正在生成缩略图…');
      return;
    }
    if (thumbnails.isEmpty || _duration <= Duration.zero) return;

    final totalMs = _duration.inMilliseconds;
    final perThumbMs = totalMs / thumbnails.length;

    // 一张缩略图在当前缩放下占多宽；太窄就跳着画，避免过度绘制
    final thumbW = perThumbMs * _pxPerMs;
    if (thumbW <= 0) return;
    final stride = thumbW < 40 ? (40 / thumbW).ceil() : 1;

    final firstIdx =
        (_viewStartMs / perThumbMs).floor().clamp(0, thumbnails.length - 1);
    final lastIdx = ((_viewStartMs + w / _pxPerMs) / perThumbMs)
        .ceil()
        .clamp(0, thumbnails.length - 1);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, _thumbTop, w, _thumbH));

    for (var i = firstIdx; i <= lastIdx; i += stride) {
      final img = cache.get(thumbnails[i]);
      if (img == null) continue;

      final x = _x(i * perThumbMs);
      final drawW = math.max(thumbW * stride, 1.0);
      final aspect = img.width / img.height;
      const dh = _thumbH;
      final dw = dh * aspect;

      canvas.save();
      canvas.clipRect(Rect.fromLTWH(x, _thumbTop, drawW, dh));
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(x, _thumbTop, dw, dh),
        Paint()..filterQuality = ui.FilterQuality.low,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  void _paintWaveform(Canvas canvas, double w, double h) {
    final waveH = h - _waveTop;
    canvas.drawRect(
      Rect.fromLTWH(0, _waveTop, w, waveH),
      Paint()..color = AppColors.panel,
    );
    if (waveform.isEmpty && waveformLoading) {
      _bandNotice(canvas, w, _waveTop, waveH, '正在分析音频…');
      return;
    }
    if (waveform.isEmpty || _duration <= Duration.zero) return;

    final totalMs = _duration.inMilliseconds.toDouble();
    final mid = _waveTop + waveH / 2;
    final paint = Paint()..color = AppColors.waveform;

    for (var px = 0; px < w.floor(); px++) {
      final ms = _viewStartMs + px / _pxPerMs;
      if (ms < 0 || ms > totalMs) continue;
      final i = ((ms / totalMs) * waveform.length)
          .floor()
          .clamp(0, waveform.length - 1);
      final amp = waveform[i] * (waveH * 0.46);
      if (amp < 0.4) continue;
      canvas.drawLine(
        Offset(px + 0.5, mid - amp),
        Offset(px + 0.5, mid + amp),
        paint,
      );
    }
  }

  /// 刻度密度自适应：始终保持 ~80px 一个标签，缩放时不会挤成一团
  void _paintRuler(Canvas canvas, double w, double viewEndMs) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, _rulerH),
      Paint()..color = AppColors.panelAlt,
    );

    const targetPx = 82.0;
    final stepMs = _niceStep(targetPx / _pxPerMs);
    final startTick = (_viewStartMs / stepMs).floor() * stepMs;
    final tickPaint = Paint()..color = AppColors.borderStrong;

    for (var ms = startTick; ms <= viewEndMs; ms += stepMs) {
      if (ms < 0) continue;
      final x = _x(ms);
      canvas.drawLine(Offset(x, _rulerH - 5), Offset(x, _rulerH), tickPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: formatTime(Duration(milliseconds: ms.round())),
          style: AppText.monoDim.copyWith(fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 3, 2));
    }

    canvas.drawLine(
      const Offset(0, _rulerH - 0.5),
      Offset(w, _rulerH - 0.5),
      Paint()..color = AppColors.border,
    );
  }

  static double _niceStep(double raw) {
    const steps = <double>[
      100,
      200,
      500,
      1000,
      2000,
      5000,
      10000,
      15000,
      30000,
      60000,
      120000,
      300000,
      600000,
      900000,
      1800000,
      3600000,
      7200000,
    ];
    for (final s in steps) {
      if (s >= raw) return s;
    }
    return steps.last;
  }

  /// 关键帧刻度。无损切割只能落在这些点上，画出来让用户能主动对齐。
  /// 太密时跳过，否则连成一条实心线，没有信息量。
  void _paintKeyframes(Canvas canvas, double viewEndMs) {
    if (keyframes.isEmpty) return;
    final paint = Paint()
      ..color = AppColors.keyframe
      ..strokeWidth = 1;

    var drawn = 0;
    double lastX = -999;
    for (final k in keyframes) {
      final ms = k.inMilliseconds.toDouble();
      if (ms < _viewStartMs) continue;
      if (ms > viewEndMs) break;
      final x = _x(ms);
      if (x - lastX < 3) continue;
      lastX = x;
      canvas.drawLine(Offset(x, _rulerH - 9), Offset(x, _rulerH - 1), paint);
      if (++drawn > 2000) break;
    }
  }

  void _paintSegments(Canvas canvas, double w, double h) {
    for (final s in segments) {
      final x1 = _x(s.start.inMilliseconds);
      final x2 = _x(s.end.inMilliseconds);
      if (x2 < 0 || x1 > w) continue;

      final sel = s.id == selectedId;
      canvas.drawRect(
        Rect.fromLTRB(x1, _rulerH, x2, h),
        Paint()..color = AppColors.segmentFill,
      );

      final edgeColor = sel ? AppColors.segmentSelected : AppColors.segment;
      final edge = Paint()
        ..color = edgeColor
        ..strokeWidth = sel ? 2.5 : 1.5;
      canvas.drawLine(Offset(x1, _rulerH), Offset(x1, h), edge);
      canvas.drawLine(Offset(x2, _rulerH), Offset(x2, h), edge);

      // 顶部实边，让片段范围在缩略图上也能看清
      canvas.drawLine(
        Offset(x1, _rulerH + 1),
        Offset(x2, _rulerH + 1),
        Paint()
          ..color = edgeColor
          ..strokeWidth = 2,
      );

      // 选中片段两端加抓手，明示「这里可以拖」
      if (sel) {
        for (final hx in [x1, x2]) {
          canvas.drawRRect(
            RRect.fromLTRBR(
              hx - 2.5,
              _rulerH + 4,
              hx + 2.5,
              _rulerH + 18,
              const Radius.circular(1.5),
            ),
            Paint()..color = edgeColor,
          );
        }
      }

      if (x2 - x1 > 46) {
        final tp = TextPainter(
          text: TextSpan(
            text: formatTime(s.duration),
            style: AppText.monoDim.copyWith(fontSize: 10, color: edgeColor),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x1 + 7, _rulerH + 4));
      }
    }
  }

  /// 已按 I 未按 O：画一条黄线 + 到播放头的半透明区，
  /// 让「正在标记中」这个状态永远可见
  void _paintPending(Canvas canvas, double h) {
    final pin = pendingIn;
    if (pin == null) return;
    final x1 = _x(pin.inMilliseconds);
    final x2 = _x(position.inMilliseconds);
    canvas.drawRect(
      Rect.fromLTRB(math.min(x1, x2), _rulerH, math.max(x1, x2), h),
      Paint()..color = AppColors.pendingFill,
    );
    canvas.drawLine(
      Offset(x1, _rulerH),
      Offset(x1, h),
      Paint()
        ..color = AppColors.pending
        ..strokeWidth = 2,
    );
  }

  void _paintPlayhead(Canvas canvas, double h) {
    final x = _x(position.inMilliseconds);
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, h),
      Paint()
        ..color = AppColors.playhead
        ..strokeWidth = 1.5,
    );
    final head = Path()
      ..moveTo(x - 5, 0)
      ..lineTo(x + 5, 0)
      ..lineTo(x, 7)
      ..close();
    canvas.drawPath(head, Paint()..color = AppColors.playhead);
  }

  @override
  bool shouldRepaint(_DetailPainter old) =>
      old.position != position ||
      old.segments != segments ||
      old.keyframes != keyframes ||
      old.waveform != waveform ||
      old.thumbnails != thumbnails ||
      old.thumbnailsLoading != thumbnailsLoading ||
      old.waveformLoading != waveformLoading ||
      old.selectedId != selectedId ||
      old.pendingIn != pendingIn;
}
