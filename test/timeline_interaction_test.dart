import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianjin/src/models/segment.dart';
import 'package:jianjin/src/ui/theme.dart';
import 'package:jianjin/src/ui/timeline/detail_timeline.dart';
import 'package:jianjin/src/ui/timeline/thumbnail_cache.dart';
import 'package:jianjin/src/ui/timeline/timeline_panel.dart';

/// 回归测试：命中测试曾经只看横坐标，导致刻度尺带虽然没有画片段，
/// 横坐标一落在片段范围内就能把片段拖走 —— 交互区与可见区错位。
const kDuration = Duration(minutes: 5);
const kSegment = Segment(
  id: 'a',
  start: Duration(seconds: 60),
  end: Duration(seconds: 120),
);

class Recorder {
  final resizes = <(String, Duration?, Duration?, bool)>[];
  final scrubs = <Duration>[];
  int scrubStarts = 0;
}

Widget harness(Recorder rec) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: DefaultTextStyle(
      style: AppText.base,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(1280, 800)),
        child: Column(
          children: [
            const Expanded(child: SizedBox.expand()),
            TimelinePanel(
              duration: kDuration,
              position: const Duration(seconds: 30),
              segments: const [kSegment],
              keyframes: const [],
              waveform: const [],
              thumbnails: const [],
              cache: ThumbnailCache(),
              selectedId: kSegment.id,
              onScrubStart: () => rec.scrubStarts++,
              onScrub: rec.scrubs.add,
              onScrubEnd: rec.scrubs.add,
              onSelect: (_) {},
              onResize: (id, s, e, commit) =>
                  rec.resizes.add((id, s, e, commit)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 片段中点在细节轨上的横坐标
double segmentCenterX(WidgetTester tester) {
  final box = tester.getRect(find.byType(DetailTimeline));
  const mid = Duration(seconds: 90); // 片段 60s..120s 的中点
  final f = mid.inMilliseconds / kDuration.inMilliseconds;
  return box.left + box.width * f;
}

void main() {
  testWidgets('刻度尺带内拖动不得移动片段（回归）', (tester) async {
    final rec = Recorder();
    await tester.pumpWidget(harness(rec));
    expect(tester.takeException(), isNull);

    final box = tester.getRect(find.byType(DetailTimeline));
    final x = segmentCenterX(tester);
    // 刻度尺带：细节轨顶部 0..18
    final start = Offset(x, box.top + TimelineBands.ruler / 2);

    final g = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await g.moveBy(const Offset(80, 0));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(
      rec.resizes,
      isEmpty,
      reason: '刻度尺带没有绘制片段，就不该能拖动片段',
    );
    expect(rec.scrubStarts, 1, reason: '刻度尺带应当只做 scrub');
    expect(rec.scrubs, isNotEmpty);
  });

  testWidgets('片段主体内拖动应整体平移且时长不变', (tester) async {
    final rec = Recorder();
    await tester.pumpWidget(harness(rec));

    final box = tester.getRect(find.byType(DetailTimeline));
    final x = segmentCenterX(tester);
    // 缩略图带，确实画着片段的位置
    final start = Offset(x, box.top + TimelineBands.thumbTop + 10);

    final g = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await g.moveBy(const Offset(60, 0));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(rec.resizes, isNotEmpty, reason: '片段主体内应当可拖动');
    expect(rec.scrubStarts, 0, reason: '拖片段时不应触发 scrub');

    final (id, s, e, _) = rec.resizes.last;
    expect(id, kSegment.id);
    expect(s, isNotNull);
    expect(e, isNotNull);
    expect(
      (e! - s!).inMilliseconds,
      closeTo(kSegment.duration.inMilliseconds, 2),
      reason: '整体平移必须保持时长不变',
    );
    expect(s.inMilliseconds, greaterThan(kSegment.start.inMilliseconds),
        reason: '向右拖动，起点应右移');
  });

  testWidgets('片段边缘拖动只改一端', (tester) async {
    final rec = Recorder();
    await tester.pumpWidget(harness(rec));

    final box = tester.getRect(find.byType(DetailTimeline));
    final f = kSegment.end.inMilliseconds / kDuration.inMilliseconds;
    final xEnd = box.left + box.width * f;
    final start = Offset(xEnd, box.top + TimelineBands.thumbTop + 10);

    final g = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await g.moveBy(const Offset(40, 0));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(rec.resizes, isNotEmpty);
    final last = rec.resizes.last;
    final s = last.$2;
    final e = last.$3;
    expect(s, isNull, reason: '拖终点不应改动起点');
    expect(e, isNotNull);
  });

  testWidgets('空白处拖动是 scrub，不碰片段', (tester) async {
    final rec = Recorder();
    await tester.pumpWidget(harness(rec));

    final box = tester.getRect(find.byType(DetailTimeline));
    // 片段之外（片头附近）
    final start = Offset(
      box.left + box.width * 0.05,
      box.top + TimelineBands.thumbTop + 10,
    );

    final g = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(rec.resizes, isEmpty);
    expect(rec.scrubStarts, 1);
  });
}
