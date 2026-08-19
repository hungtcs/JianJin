@Tags(['shots'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianjin/src/ui/about_dialog.dart';
import 'package:jianjin/src/ui/theme.dart';

/// 把界面渲染成 PNG 用于人工查看。
/// 关键点：widget 测试里 Image.asset 的解码是真异步，被 testWidgets 的
/// 假时钟挡住，必须在 runAsync 里 precacheImage，否则图片永远是空白。
Future<void> pumpAndLoadImages(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(w);
  await tester.runAsync(() async {
    for (final img in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(img.image, tester.element(find.byWidget(img)));
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('render about', (tester) async {
    tester.view.physicalSize = const Size(900, 620);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await pumpAndLoadImages(
      tester,
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: AppText.base,
          child: Container(
            color: AppColors.bg,
            child: AboutPanel(
              version: '0.1.0',
              ffmpegVersion: 'ffmpeg version 8.1.2',
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(AboutPanel),
      matchesGoldenFile('shots/about.png'),
    );
  });
}
