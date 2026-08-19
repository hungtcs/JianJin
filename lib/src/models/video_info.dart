import 'package:flutter/foundation.dart';

@immutable
class VideoInfo {
  const VideoInfo({
    required this.path,
    required this.duration,
    required this.width,
    required this.height,
    required this.videoCodec,
    required this.audioCodec,
    required this.frameRate,
    required this.container,
    this.keyframes = const <Duration>[],
  });

  final String path;
  final Duration duration;
  final int width;
  final int height;
  final String videoCodec;
  final String audioCodec;
  final double frameRate;
  final String container;

  /// 关键帧时间点，升序。无损切割只能落在这些点上。
  final List<Duration> keyframes;

  bool get hasKeyframes => keyframes.isNotEmpty;

  Duration get frameDuration => frameRate > 0
      ? Duration(microseconds: (1000000 / frameRate).round())
      : const Duration(milliseconds: 40);

  VideoInfo copyWith({List<Duration>? keyframes}) => VideoInfo(
        path: path,
        duration: duration,
        width: width,
        height: height,
        videoCodec: videoCodec,
        audioCodec: audioCodec,
        frameRate: frameRate,
        container: container,
        keyframes: keyframes ?? this.keyframes,
      );

  /// 起点向前吸附到 <= t 的最近关键帧，否则会丢内容。
  Duration snapStartToKeyframe(Duration t) {
    if (keyframes.isEmpty) return t;
    var lo = 0, hi = keyframes.length - 1, best = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (keyframes[mid] <= t) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return keyframes[best];
  }

  /// 终点向后吸附到 >= t 的最近关键帧，宁可多留也不丢内容。
  Duration snapEndToKeyframe(Duration t) {
    if (keyframes.isEmpty) return t;
    var lo = 0, hi = keyframes.length - 1;
    Duration? best;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (keyframes[mid] >= t) {
        best = keyframes[mid];
        hi = mid - 1;
      } else {
        lo = mid + 1;
      }
    }
    return best ?? duration;
  }

  /// 吸附会带来多大偏移，用于在 UI 上提示「这一刀会偏多少」
  Duration snapDrift(Duration t) {
    if (keyframes.isEmpty) return Duration.zero;
    final db = (t - snapStartToKeyframe(t)).abs();
    final da = (snapEndToKeyframe(t) - t).abs();
    return db < da ? db : da;
  }
}
