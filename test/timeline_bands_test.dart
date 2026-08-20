import 'package:flutter_test/flutter_test.dart';
import 'package:jianjin/src/ui/timeline/detail_timeline.dart';

/// 缩略图与波形可在设置里关闭。关闭时对应带子整条消失、轨道变矮，
/// 而不是留一条空白灰带；两者都关时仍要留出足够高度，
/// 否则片段与播放头会被压成一条线，看不清也拖不动。
void main() {
  group('分带高度', () {
    test('两者都开时，波形吃掉刻度尺与缩略图之外的全部空间', () {
      const b = TimelineBands(height: 200);
      expect(b.thumbTop, TimelineBands.ruler);
      expect(b.waveTop, TimelineBands.ruler + TimelineBands.thumbHeight);
      expect(
        b.waveHeight,
        200 - TimelineBands.ruler - TimelineBands.thumbHeight,
      );
      expect(b.totalHeight, 200);
    });

    test('关掉缩略图后，波形接管它的空间', () {
      const withThumbs = TimelineBands(height: 200);
      const noThumbs = TimelineBands(thumbnails: false, height: 200);

      expect(noThumbs.waveTop, TimelineBands.ruler, reason: '波形应上移到刻度尺下方');
      expect(
        noThumbs.waveHeight,
        withThumbs.waveHeight + TimelineBands.thumbHeight,
        reason: '腾出的空间应归波形，而不是留白',
      );
      expect(noThumbs.totalHeight, 200, reason: '总高不变，只是内部重新分配');
    });

    test('关掉波形后，轨道相应变矮而不是留空带', () {
      const b = TimelineBands(waveform: false, height: 200);
      expect(b.waveHeight, 0);
      expect(b.totalHeight, TimelineBands.ruler + TimelineBands.thumbHeight);
    });

    test('两者都关时仍保留最小高度，播放头与片段才画得下', () {
      const b = TimelineBands(thumbnails: false, waveform: false, height: 200);
      expect(b.waveHeight, 0);
      expect(b.totalHeight, TimelineBands.minHeight);
      expect(b.totalHeight, greaterThan(TimelineBands.ruler),
          reason: '刻度尺以下必须留出可视可拖的区域');
    });

    test('高度被拖得过小时，波形不小于下限', () {
      const b = TimelineBands(height: 10);
      expect(b.waveHeight, TimelineBands.minWave);
      expect(b.totalHeight, greaterThanOrEqualTo(TimelineBands.minHeight));
    });

    test('copyWith 只改高度，开关保持不变', () {
      const b = TimelineBands(thumbnails: false, waveform: true, height: 96);
      final c = b.copyWith(height: 300);
      expect(c.thumbnails, isFalse);
      expect(c.waveform, isTrue);
      expect(c.height, 300);
    });

    test('相同配置相等，可用于 shouldRepaint 判定', () {
      expect(const TimelineBands(height: 96), const TimelineBands(height: 96));
      expect(const TimelineBands(height: 96) == const TimelineBands(height: 97),
          isFalse);
    });
  });
}
