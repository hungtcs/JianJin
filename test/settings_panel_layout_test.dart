import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianjin/src/settings.dart';
import 'package:jianjin/src/ui/settings_panel.dart';
import 'package:jianjin/src/ui/theme.dart';

/// 设置面板加了「外部程序」一节后变高不少。这类改动 analyze 与 build
/// 全绿也照样一跑就渲染溢出，只有真正 pump 才抓得到——尤其是小窗口。
///
/// 版本探测走注入的假实现：渲染测试不该依赖本机装没装 ffmpeg，
/// 真起子进程还会在测试结束时留下未完成的异步任务。
Future<String?> fakeProbe(String exe) async =>
    'ffmpeg version 7.1 Copyright (c) 2000-2024 the FFmpeg developers';
Widget harness(Widget child, Size size) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: DefaultTextStyle(
      style: AppText.base,
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: child,
      ),
    ),
  );
}

void main() {
  // 从常规窗口一路缩到比面板本身还小
  const sizes = <Size>[
    Size(1280, 800),
    Size(900, 600),
    Size(640, 480),
    Size(500, 360),
    Size(420, 300),
  ];

  for (final size in sizes) {
    testWidgets('${size.width.toInt()}x${size.height.toInt()} 下不溢出',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(
        SettingsPanel(
          settings: AppSettings.memory(),
          onClose: () {},
          probe: fakeProbe,
        ),
        size,
      ));
      // 外部程序一节会异步探测版本，让它跑完再断言
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('内容超出可视高度时可以滚动，而不是被裁掉', (tester) async {
    const size = Size(500, 360);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(
      SettingsPanel(
        settings: AppSettings.memory(),
        onClose: () {},
        probe: fakeProbe,
      ),
      size,
    ));
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final sc = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(sc.child, isNotNull);

    // 「关闭」按钮固定在底部，不能被滚出视野
    expect(find.text('关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 回归：容器带左右内边距时，ScrollBehavior 加在 SingleChildScrollView 外面的
  // 滚动条会被挤进内边距里侧，离面板边缘 24px 悬在半空。视口必须铺满面板宽度，
  // 内容缩进则由滚动视图自己的 padding 负责。
  testWidgets('滚动视口铺满面板宽度，滚动条不落在内边距里', (tester) async {
    const size = Size(900, 500);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(
      SettingsPanel(
        settings: AppSettings.memory(),
        onClose: () {},
        probe: fakeProbe,
      ),
      size,
    ));
    await tester.pump();

    final scroll = find.byType(SingleChildScrollView);
    final scrollWidth = tester.getSize(scroll).width;
    expect(
      scrollWidth,
      greaterThan(440),
      reason: '面板宽 460，视口只留 6px 给滚动条；'
          '若被容器的左右各 24px 内边距吃掉就只有 412',
    );

    // 内容仍与固定的标题、底部按钮左对齐
    final panelLeft = tester.getTopLeft(scroll).dx;
    expect(tester.getTopLeft(find.text('设置')).dx, panelLeft + 24);
    expect(tester.getTopLeft(find.text('外部程序')).dx, panelLeft + 24);
  });

  testWidgets('外部程序一节把两个二进制都列出来', (tester) async {
    const size = Size(900, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(
      SettingsPanel(
        settings: AppSettings.memory(),
        onClose: () {},
        probe: fakeProbe,
      ),
      size,
    ));
    await tester.pump();

    expect(find.text('外部程序'), findsOneWidget);
    expect(find.text('ffmpeg'), findsOneWidget);
    expect(find.text('ffprobe'), findsOneWidget);
    // 每个二进制一个「选择…」
    expect(find.text('选择…'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
