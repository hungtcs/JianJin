import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianjin/src/models/video_info.dart';
import 'package:jianjin/src/services/ffmpeg_service.dart';
import 'package:path/path.dart' as p;

/// 导出曾经用 ffmpeg -y 静默覆盖同名文件，会不声不响毁掉上一次的成果。
/// 这里锁定命名规则与冲突处置。
VideoInfo infoFor(String path) => VideoInfo(
      path: path,
      duration: const Duration(minutes: 10),
      width: 1920,
      height: 1080,
      videoCodec: 'h264',
      audioCodec: 'aac',
      frameRate: 30,
      container: 'mp4',
    );

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('jj_naming_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('输出命名', () {
    test('沿用源文件名并按三位序号编号', () {
      final info = infoFor('/videos/holiday.mp4');
      expect(FfmpegService.outputNameFor(info, 0), 'holiday_001.mp4');
      expect(FfmpegService.outputNameFor(info, 9), 'holiday_010.mp4');
      expect(FfmpegService.outputNameFor(info, 122), 'holiday_123.mp4');
    });

    test('保留原扩展名', () {
      expect(FfmpegService.outputNameFor(infoFor('/v/a.mkv'), 0), 'a_001.mkv');
      expect(FfmpegService.outputNameFor(infoFor('/v/b.mov'), 0), 'b_001.mov');
    });

    test('规划的路径数量与片段数一致且互不重复', () {
      final outs = FfmpegService.plannedOutputs(
        info: infoFor('/videos/clip.mp4'),
        segmentCount: 5,
        outputDir: '/out',
      );
      expect(outs.length, 5);
      expect(outs.toSet().length, 5);
      expect(outs.first, p.join('/out', 'clip_001.mp4'));
    });
  });

  group('自动改名', () {
    test('目标不存在时原样返回', () {
      final path = p.join(tmp.path, 'a.mp4');
      expect(FfmpegService.freePathFor(path), path);
    });

    test('目标已存在时加序号后缀', () {
      final path = p.join(tmp.path, 'a.mp4');
      File(path).writeAsStringSync('x');
      expect(FfmpegService.freePathFor(path), p.join(tmp.path, 'a-2.mp4'));
    });

    test('连续占用时继续递增', () {
      for (final name in ['a.mp4', 'a-2.mp4', 'a-3.mp4']) {
        File(p.join(tmp.path, name)).writeAsStringSync('x');
      }
      expect(
        FfmpegService.freePathFor(p.join(tmp.path, 'a.mp4')),
        p.join(tmp.path, 'a-4.mp4'),
      );
    });

    test('改名不会碰原文件', () {
      final path = p.join(tmp.path, 'a.mp4');
      File(path).writeAsStringSync('original');
      FfmpegService.freePathFor(path);
      expect(File(path).readAsStringSync(), 'original');
    });
  });

  group('冲突检测', () {
    test('只报告确实存在的目标文件', () {
      final info = infoFor(p.join(tmp.path, 'src.mp4'));
      File(p.join(tmp.path, 'src_002.mp4')).writeAsStringSync('x');

      final planned = FfmpegService.plannedOutputs(
        info: info,
        segmentCount: 3,
        outputDir: tmp.path,
      );
      final existing = planned.where((f) => File(f).existsSync()).toList();

      expect(existing, [p.join(tmp.path, 'src_002.mp4')]);
    });

    test('目录干净时没有冲突', () {
      final planned = FfmpegService.plannedOutputs(
        info: infoFor(p.join(tmp.path, 'src.mp4')),
        segmentCount: 3,
        outputDir: tmp.path,
      );
      expect(planned.where((f) => File(f).existsSync()), isEmpty);
    });
  });
}
