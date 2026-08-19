import 'package:flutter_test/flutter_test.dart';
import 'package:jianjin/src/models/segment.dart';
import 'package:jianjin/src/models/video_info.dart';
import 'package:jianjin/src/ui/theme.dart';

Segment seg(String id, int startS, int endS) => Segment(
      id: id,
      start: Duration(seconds: startS),
      end: Duration(seconds: endS),
    );

VideoInfo infoWithKeyframes(List<int> seconds) => VideoInfo(
      path: '/tmp/x.mp4',
      duration: const Duration(seconds: 100),
      width: 1920,
      height: 1080,
      videoCodec: 'h264',
      audioCodec: 'aac',
      frameRate: 25,
      container: 'mp4',
      keyframes: seconds.map((s) => Duration(seconds: s)).toList(),
    );

void main() {
  group('mergeSegments', () {
    test('不重叠的片段保持原样并按时间排序', () {
      final out = mergeSegments([seg('b', 30, 40), seg('a', 0, 10)]);
      expect(out.length, 2);
      expect(out[0].start, const Duration(seconds: 0));
      expect(out[1].start, const Duration(seconds: 30));
    });

    test('重叠片段合并成一段', () {
      final out = mergeSegments([seg('a', 0, 20), seg('b', 10, 30)]);
      expect(out.length, 1);
      expect(out.first.start, Duration.zero);
      expect(out.first.end, const Duration(seconds: 30));
    });

    test('被完全包含的片段不会缩短外层片段', () {
      final out = mergeSegments([seg('a', 0, 50), seg('b', 10, 20)]);
      expect(out.length, 1);
      expect(out.first.end, const Duration(seconds: 50));
    });

    test('三段连锁重叠合并成一段', () {
      final out = mergeSegments([
        seg('a', 0, 10),
        seg('b', 8, 18),
        seg('c', 16, 26),
      ]);
      expect(out.length, 1);
      expect(out.first.end, const Duration(seconds: 26));
    });
  });

  group('关键帧吸附（无损切割的正确性依赖于此）', () {
    final info = infoWithKeyframes([0, 10, 20, 30, 40]);

    test('起点向前吸附，避免丢内容', () {
      expect(info.snapStartToKeyframe(const Duration(seconds: 25)),
          const Duration(seconds: 20));
    });

    test('终点向后吸附，宁可多留', () {
      expect(info.snapEndToKeyframe(const Duration(seconds: 25)),
          const Duration(seconds: 30));
    });

    test('正好落在关键帧上时两侧都返回自身', () {
      expect(info.snapStartToKeyframe(const Duration(seconds: 20)),
          const Duration(seconds: 20));
      expect(info.snapEndToKeyframe(const Duration(seconds: 20)),
          const Duration(seconds: 20));
    });

    test('早于首个关键帧的起点返回首个关键帧', () {
      expect(info.snapStartToKeyframe(Duration.zero), Duration.zero);
    });

    test('晚于末个关键帧的终点回落到总时长', () {
      expect(info.snapEndToKeyframe(const Duration(seconds: 90)),
          const Duration(seconds: 100));
    });

    test('无关键帧信息时原样返回，不应破坏时间', () {
      const bare = VideoInfo(
        path: '/tmp/y.mp4',
        duration: Duration(seconds: 100),
        width: 640,
        height: 480,
        videoCodec: 'h264',
        audioCodec: 'aac',
        frameRate: 30,
        container: 'mp4',
      );
      const t = Duration(seconds: 33);
      expect(bare.snapStartToKeyframe(t), t);
      expect(bare.snapEndToKeyframe(t), t);
    });

    test('吸附偏移取两侧较小者', () {
      expect(info.snapDrift(const Duration(seconds: 22)),
          const Duration(seconds: 2));
      expect(info.snapDrift(const Duration(seconds: 28)),
          const Duration(seconds: 2));
    });
  });

  group('formatTime', () {
    test('一小时以内省略小时位', () {
      expect(formatTime(const Duration(minutes: 3, seconds: 5)), '03:05');
    });

    test('超过一小时带上小时位', () {
      expect(
        formatTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('带毫秒时显示两位', () {
      expect(
        formatTime(const Duration(seconds: 5, milliseconds: 120),
            withMillis: true),
        '00:05.12',
      );
    });
  });
}
