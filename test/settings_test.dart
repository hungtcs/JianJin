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

    test('未指定 ffmpeg / ffprobe 路径时为 null，交给自动查找', () {
      final s = AppSettings.memory();
      expect(s.ffmpegPath, isNull);
      expect(s.ffprobePath, isNull);
    });

    test('配置里存着非字符串的路径时当作未指定，而不是崩', () {
      final s = AppSettings.memory({'ffmpegPath': 42});
      expect(s.ffmpegPath, isNull);
    });
  });

  group('外部程序路径', () {
    test('设置后可读回', () {
      final s = AppSettings.memory();
      s.ffmpegPath = '/opt/tools/ffmpeg';
      s.ffprobePath = '/opt/tools/ffprobe';
      expect(s.ffmpegPath, '/opt/tools/ffmpeg');
      expect(s.ffprobePath, '/opt/tools/ffprobe');
    });

    // 空串与 null 必须归一：否则「清除过」和「从未设置」在 locator
    // 那边是两种行为，用户点了清除却发现还是没回到自动查找
    test('空串、纯空白、null 都等同于未指定', () {
      for (final v in <String?>['', '   ', null]) {
        final s = AppSettings.memory({'ffmpegPath': '/x/ffmpeg'});
        s.ffmpegPath = v;
        expect(s.ffmpegPath, isNull, reason: '输入 ${v.runtimeType}:"$v"');
      }
    });

    test('两端空白会被去掉——拖进来的路径常带空格', () {
      final s = AppSettings.memory();
      s.ffmpegPath = '  /opt/tools/ffmpeg  ';
      expect(s.ffmpegPath, '/opt/tools/ffmpeg');
    });

    test('值有变化才通知', () {
      final s = AppSettings.memory({'ffmpegPath': '/x/ffmpeg'});
      var n = 0;
      s.addListener(() => n++);

      s.ffmpegPath = '/x/ffmpeg';
      expect(n, 0);
      s.ffmpegPath = '  /x/ffmpeg  '; // 归一后相同
      expect(n, 0, reason: '归一化后相同的值不该触发写盘');

      s.ffmpegPath = '/y/ffmpeg';
      expect(n, 1);
      s.ffmpegPath = null;
      expect(n, 2);
    });

    test('ffmpeg 与 ffprobe 互不影响', () {
      final s = AppSettings.memory();
      s.ffmpegPath = '/x/ffmpeg';
      expect(s.ffprobePath, isNull);
      s.ffprobePath = '/y/ffprobe';
      expect(s.ffmpegPath, '/x/ffmpeg');
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
