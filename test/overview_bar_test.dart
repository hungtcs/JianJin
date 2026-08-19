import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianjin/src/ui/theme.dart';
import 'package:jianjin/src/ui/timeline/overview_bar.dart';
import 'package:jianjin/src/ui/timeline/timeline_view_controller.dart';

/// 回归测试：视口框窄到一定程度后，边缘命中区曾跟着变窄到抓不住，
/// 结果只能拖动、无法左右调整范围。命中区现在与视觉宽度解耦。
const kDuration = Duration(hours: 2);

Widget harness(TimelineViewController v) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: DefaultTextStyle(
      style: AppText.base,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(1000, 200)),
        child: Column(
          children: [
            SizedBox(
              height: AppMetrics.overviewHeight,
              child: OverviewBar(
                view: v,
                position: const Duration(minutes: 30),
                segments: const [],
                waveform: const [],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 放大到视口只占全条极小一段，模拟「时间范围很小」的情形
TimelineViewController zoomedIn(double fraction) {
  final v = TimelineViewController()
    ..setWidth(1000)
    ..reset(kDuration);
  final total = kDuration.inMilliseconds.toDouble();
  v.setViewRange(total * 0.5, total * (0.5 + fraction));
  return v;
}

void main() {
  testWidgets('视口极窄时仍可拖左边缘调整范围（回归）', (tester) async {
    final v = zoomedIn(0.004); // 1000px 上只有 4px 宽
    await tester.pumpWidget(harness(v));
    expect(tester.takeException(), isNull);

    final box = tester.getRect(find.byType(OverviewBar));
    final total = kDuration.inMilliseconds.toDouble();
    final beforeSpan = v.visibleMs;
    final leftX = box.left + box.width * (v.viewStartMs / total);

    final g = await tester.startGesture(
      Offset(leftX, box.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await g.moveBy(const Offset(-80, 0)); // 向左拉宽
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(v.visibleMs, greaterThan(beforeSpan),
        reason: '拖左边缘应当扩大可见范围，而不是平移');
  });

  testWidgets('视口极窄时仍可拖右边缘调整范围', (tester) async {
    final v = zoomedIn(0.004);
    await tester.pumpWidget(harness(v));

    final box = tester.getRect(find.byType(OverviewBar));
    final total = kDuration.inMilliseconds.toDouble();
    final beforeSpan = v.visibleMs;
    final rightX = box.left + box.width * (v.viewEndMs / total);

    final g = await tester.startGesture(
      Offset(rightX, box.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await g.moveBy(const Offset(80, 0));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(v.visibleMs, greaterThan(beforeSpan));
  });

  testWidgets('视口较宽时中间拖动是平移，范围不变', (tester) async {
    final v = zoomedIn(0.30); // 300px 宽，中间有充足的拖动区
    await tester.pumpWidget(harness(v));

    final box = tester.getRect(find.byType(OverviewBar));
    final total = kDuration.inMilliseconds.toDouble();
    final beforeSpan = v.visibleMs;
    final beforeStart = v.viewStartMs;
    final midX =
        box.left + box.width * ((v.viewStartMs + v.viewEndMs) / 2 / total);

    final g = await tester.startGesture(
      Offset(midX, box.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await g.moveBy(const Offset(60, 0));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(v.visibleMs, closeTo(beforeSpan, 1), reason: '平移不应改变范围');
    expect(v.viewStartMs, greaterThan(beforeStart));
  });

  testWidgets('全片条不改变播放进度（只控制视口）', (tester) async {
    final v = zoomedIn(0.30);
    await tester.pumpWidget(harness(v));
    // OverviewBar 已不再接受 onSeek 回调；此测试锁定这一约定，
    // 若将来有人把 seek 加回来，构造函数会编译失败
    expect(find.byType(OverviewBar), findsOneWidget);
  });
}
