import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 两条时间轴共享的视图状态（可见起点 + 缩放）。
///
/// 提取出来的原因：全局条要能拖动细节轨的视口，而「播放跟随」和「用户手动平移」
/// 必须有唯一的裁决点——否则两者会每帧互相覆盖，表现为抖动。
class TimelineViewController extends ChangeNotifier {
  double _viewStartMs = 0;
  double _pxPerMs = 0.02;
  double _width = 0;
  Duration _duration = Duration.zero;

  /// 是否自动跟随播放头。用户一旦手动平移/缩放就交出控制权。
  bool _follow = true;

  /// reset 时若宽度尚未知（首帧布局前），把「整片铺满」挂起，
  /// 等 setWidth 到位再兑现。否则视图会停在默认缩放上，只显示一小段。
  bool _pendingFit = false;

  static const _minPxPerMs = 0.00002;
  static const _maxPxPerMs = 0.5; // 500 px/秒，足够逐帧对齐

  double get viewStartMs => _viewStartMs;
  double get pxPerMs => _pxPerMs;
  double get width => _width;
  Duration get duration => _duration;
  bool get following => _follow;

  double get visibleMs => _pxPerMs <= 0 ? 0 : _width / _pxPerMs;
  double get viewEndMs => _viewStartMs + visibleMs;

  Duration get viewStart => Duration(milliseconds: _viewStartMs.round());
  Duration get viewEnd => Duration(milliseconds: viewEndMs.round());

  /// 整片是否已完全可见（此时平移无意义）
  bool get fitsEntirely => visibleMs >= _duration.inMilliseconds;

  double xOf(Duration t) => (t.inMilliseconds - _viewStartMs) * _pxPerMs;

  Duration timeAt(double x) {
    final ms = _viewStartMs + x / _pxPerMs;
    final total = _duration.inMilliseconds;
    return Duration(milliseconds: ms.clamp(0, total.toDouble()).round());
  }

  void setWidth(double w) {
    if (w <= 0 || (w - _width).abs() < 0.5) return;
    _width = w;
    if (_pendingFit && _duration.inMilliseconds > 0) {
      _pxPerMs = _width / _duration.inMilliseconds;
      _viewStartMs = 0;
      _pendingFit = false;
    }
    _clamp();
    notifyListeners();
  }

  /// 打开新文件时重置：整片铺满，恢复跟随
  void reset(Duration duration) {
    _duration = duration;
    _viewStartMs = 0;
    _follow = true;
    if (_width > 0 && duration.inMilliseconds > 0) {
      _pxPerMs = _width / duration.inMilliseconds;
      _pendingFit = false;
    } else {
      _pendingFit = true;
    }
    _clamp();
    notifyListeners();
  }

  void _clamp() {
    final total = _duration.inMilliseconds.toDouble();
    if (total <= 0 || _width <= 0) return;

    // 缩放下限：整片刚好铺满，不允许再缩小（否则两侧留空很难看）
    final fit = _width / total;
    _pxPerMs = _pxPerMs.clamp(math.max(fit, _minPxPerMs), _maxPxPerMs);

    final vis = visibleMs;
    _viewStartMs = vis >= total ? 0 : _viewStartMs.clamp(0, total - vis);
  }

  // ------------------------------------------------------------ 用户手动操作

  /// 用户手动平移/缩放：交出跟随权。
  /// 不做「N 秒后自动恢复」——那会在用户正看着某段时突然把视图拽走。
  /// 恢复条件见 [followPlayhead]：等播放头自己走进视野再接管。
  void _handOver() => _follow = false;

  void panByPixels(double dx) {
    if (fitsEntirely) return;
    _handOver();
    _viewStartMs += dx / _pxPerMs;
    _clamp();
    notifyListeners();
  }

  /// 把视口起点直接挪到某处（全局条拖动用）
  void panToStart(double startMs) {
    if (fitsEntirely) return;
    _handOver();
    _viewStartMs = startMs;
    _clamp();
    notifyListeners();
  }

  /// 让某个时间点居中显示（全局条点击空白处用）
  void centerOn(Duration t) {
    if (fitsEntirely) return;
    _handOver();
    _viewStartMs = t.inMilliseconds - visibleMs / 2;
    _clamp();
    notifyListeners();
  }

  void zoomAt(double factor, double anchorX) {
    final anchorMs = _viewStartMs + anchorX / _pxPerMs;
    _handOver();
    _pxPerMs *= factor;
    _clamp();
    _viewStartMs = anchorMs - anchorX / _pxPerMs;
    _clamp();
    notifyListeners();
  }

  /// 直接设定可见范围（全局条拖视口边缘用）。
  /// 拖边缘同时改变起点和缩放，所以不能复用 panToStart / zoomAt。
  void setViewRange(double startMs, double endMs) {
    if (_width <= 0) return;
    final total = _duration.inMilliseconds.toDouble();
    if (total <= 0) return;

    var a = startMs.clamp(0.0, total);
    var b = endMs.clamp(0.0, total);
    if (b < a) {
      final t = a;
      a = b;
      b = t;
    }

    // 视野不能小于最大缩放允许的宽度，否则拖到最后会失控
    final minSpan = _width / _maxPxPerMs;
    if (b - a < minSpan) b = a + minSpan;
    if (b > total) {
      b = total;
      a = math.max(0.0, b - minSpan);
    }

    _handOver();
    _pxPerMs = _width / (b - a);
    _viewStartMs = a;
    _clamp();
    notifyListeners();
  }

  void zoomTo(double pxPerMs, double anchorX) {
    final anchorMs = _viewStartMs + anchorX / _pxPerMs;
    _handOver();
    _pxPerMs = pxPerMs;
    _clamp();
    _viewStartMs = anchorMs - anchorX / _pxPerMs;
    _clamp();
    notifyListeners();
  }

  /// 显式跳转（点击时间轴 seek）后应恢复跟随——用户明确表达了「我要去那里」
  void resumeFollow() {
    if (_follow) return;
    _follow = true;
    notifyListeners();
  }

  // ------------------------------------------------------------ 播放跟随

  /// 播放头位置更新时调用。
  ///
  /// 抖动的根因是跟随和手动平移每帧互相覆盖，这里用两条规则彻底分开：
  /// 1. 交出控制权后**绝不**主动移动视图；
  /// 2. 直到播放头自己走进当前视野，才悄悄收回控制权——
  ///    此时视图不需要移动，所以不会有跳动。
  void followPlayhead(Duration position) {
    if (_width <= 0 || fitsEntirely) return;
    final p = position.inMilliseconds.toDouble();
    final vis = visibleMs;

    if (!_follow) {
      if (p >= _viewStartMs && p <= _viewStartMs + vis) {
        _follow = true; // 播放追上了视野，无声接管，视图不动
      }
      return;
    }

    // 跟随中：播放头逼近右边缘时整屏前推，而不是每帧微调
    // （每帧微调会让缩略图和刻度持续滑动，看着就是抖）
    final trigger = _viewStartMs + vis * 0.82;
    if (p > trigger || p < _viewStartMs) {
      _viewStartMs = p - vis * 0.2;
      _clamp();
      notifyListeners();
    }
  }
}
