import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianjin/src/models/segment.dart';
import 'package:jianjin/src/ui/theme.dart';
import 'package:jianjin/src/ui/timeline/thumbnail_cache.dart';
import 'package:jianjin/src/ui/timeline/timeline_panel.dart';

/// 回归测试：TimelinePanel 曾经在 Column 里因为
/// `Row(crossAxisAlignment: stretch)` 拿到无界高度而崩溃
/// （BoxConstraints forces an infinite height）。
///
/// 这类布局错误编译期查不出、单元测试也碰不到，只有真正渲染才会暴露。
Widget harness(Widget child, {Size size = const Size(1280, 800)}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: DefaultTextStyle(
      style: AppText.base,
      child: MediaQuery(
        data: MediaQueryData(size: size),
        // 关键：放进 Column，复现真实场景下的**无界高度**约束
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            const Expanded(child: SizedBox.expand()),
            child,
          ],
        ),
      ),
    ),
  );
}

TimelinePanel buildPanel({
  Duration duration = const Duration(minutes: 5),
  List<Segment> segments = const [],
  List<double> waveform = const [],
  List<Duration> keyframes = const [],
}) {
  return TimelinePanel(
    duration: duration,
    position: const Duration(seconds: 30),
    segments: segments,
    keyframes: keyframes,
    waveform: waveform,
    thumbnails: const [],
    cache: ThumbnailCache(),
    onScrubStart: () {},
    onScrub: (_) {},
    onScrubEnd: (_) {},
    onSelect: (_) {},
    onResize: (_, __, ___, ____) {},
  );
}

void main() {
  testWidgets('在无界高度的 Column 中渲染不应抛异常', (tester) async {
    await tester.pumpWidget(harness(buildPanel()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('两条轨的高度符合设计 token', (tester) async {
    await tester.pumpWidget(harness(buildPanel()));
    expect(tester.takeException(), isNull);

    final panel = tester.getSize(find.byType(TimelinePanel));
    expect(
      panel.height,
      AppMetrics.overviewHeight + AppMetrics.detailHeight,
      reason: '面板总高应等于两条轨之和，不应被撑开或压缩',
    );
  });

  testWidgets('带片段与波形数据时渲染正常', (tester) async {
    await tester.pumpWidget(harness(buildPanel(
      segments: const [
        Segment(
          id: 'a',
          start: Duration(seconds: 10),
          end: Duration(seconds: 40),
        ),
        Segment(
          id: 'b',
          start: Duration(seconds: 90),
          end: Duration(seconds: 130),
        ),
      ],
      waveform: [for (var i = 0; i < 500; i++) (i % 50) / 50.0],
      keyframes: [
        for (var i = 0; i < 150; i++) Duration(seconds: i * 2),
      ],
    )));
    expect(tester.takeException(), isNull);
  });

  testWidgets('时长为零（未打开文件）时不应崩溃', (tester) async {
    await tester.pumpWidget(harness(buildPanel(duration: Duration.zero)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗口下不应溢出', (tester) async {
    await tester.pumpWidget(harness(
      buildPanel(),
      size: const Size(420, 500),
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('两条轨都带层级标签，消除「两条音轨」的误解', (tester) async {
    await tester.pumpWidget(harness(buildPanel()));
    expect(find.text('全片'), findsOneWidget);
    expect(find.text('细节'), findsOneWidget);
  });
}
