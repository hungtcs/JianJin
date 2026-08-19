import 'package:flutter/foundation.dart';

import 'video_info.dart';

enum ExportMode {
  /// 无损：零重编码、极快、画质不变。
  /// 起点必须向前吸附到关键帧（无法从 GOP 中间开始 copy），
  /// 终点则可以精确切——解码器到那里停就是了，不需要吸附。
  lossless,

  /// 精确：重编码，边界帧级准确。慢且有画质损失。
  precise,
}

extension ExportModeLabel on ExportMode {
  String get label => switch (this) {
        ExportMode.lossless => '无损',
        ExportMode.precise => '精确',
      };

  String get hint => switch (this) {
        ExportMode.lossless => '零重编码，画质不变；起点会对齐到关键帧',
        ExportMode.precise => '重编码，边界准确；较慢且有画质损失',
      };
}

/// 一个片段在给定模式下**实际会导出**的区间。
/// 界面必须按这个显示，而不是按用户标记的区间——否则就是在撒谎。
@immutable
class ExportRange {
  const ExportRange({
    required this.start,
    required this.end,
    required this.requestedStart,
    required this.requestedEnd,
  });

  final Duration start;
  final Duration end;
  final Duration requestedStart;
  final Duration requestedEnd;

  Duration get duration => end - start;
  Duration get requestedDuration => requestedEnd - requestedStart;

  /// 实际比请求多出来的时长（无损模式下由起点吸附造成）
  Duration get drift => duration - requestedDuration;

  bool get hasDrift => drift.inMilliseconds.abs() >= 100;

  static ExportRange of(VideoInfo info, Duration start, Duration end,
      ExportMode mode) {
    if (mode == ExportMode.precise) {
      return ExportRange(
        start: start,
        end: end,
        requestedStart: start,
        requestedEnd: end,
      );
    }
    return ExportRange(
      // 起点向前吸附：不这样做无法无损 copy
      start: info.snapStartToKeyframe(start),
      // 终点精确：向后吸附会白白多包一整个 GOP，这是之前的设计错误
      end: end,
      requestedStart: start,
      requestedEnd: end,
    );
  }
}
