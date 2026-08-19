import 'package:flutter_test/flutter_test.dart';
import 'package:jianjin/src/models/export_mode.dart';
import 'package:jianjin/src/settings.dart';

void main() {
  group('默认值', () {
    test('缩略图与波形默认开启', () {
      final s = AppSettings.memory();
      expect(s.thumbnailsEnabled, isTrue);
      expect(s.waveformEnabled, isTrue);
    });

    test('默认导出模式为无损', () {
      expect(AppSettings.memory().exportMode, ExportMode.lossless);
    });

    test('配置文件缺字段时逐项回落到默认值，而不是整体失效', () {
      final s = AppSettings.memory({'waveform': false});
      expect(s.waveformEnabled, isFalse);
      expect(s.thumbnailsEnabled, isTrue, reason: '未写入的项应保持默认');
      expect(s.exportMode, ExportMode.lossless);
    });

    test('配置里存着无法识别的导出模式时回落到无损', () {
      final s = AppSettings.memory({'exportMode': 'nonsense'});
      expect(s.exportMode, ExportMode.lossless);
    });
  });

  group('读写', () {
    test('改动后立即可读回', () {
      final s = AppSettings.memory();
      s.thumbnailsEnabled = false;
      s.exportMode = ExportMode.precise;
      expect(s.thumbnailsEnabled, isFalse);
      expect(s.exportMode, ExportMode.precise);
    });

    test('值有变化才通知，避免无谓重建', () {
      final s = AppSettings.memory();
      var n = 0;
      s.addListener(() => n++);

      s.thumbnailsEnabled = true; // 与当前值相同
      expect(n, 0);

      s.thumbnailsEnabled = false;
      expect(n, 1);
    });

    test('时间轴高度被夹在合理范围内', () {
      final s = AppSettings.memory();
      s.timelineHeight = 5;
      expect(s.timelineHeight, greaterThanOrEqualTo(48.0));
      s.timelineHeight = 99999;
      expect(s.timelineHeight, lessThanOrEqualTo(420.0));
    });

    test('缩略图数量被夹在合理范围内', () {
      final s = AppSettings.memory();
      s.thumbnailCount = 1;
      expect(s.thumbnailCount, greaterThanOrEqualTo(40));
      s.thumbnailCount = 100000;
      expect(s.thumbnailCount, lessThanOrEqualTo(2000));
    });
  });
}
