@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:jianjin/src/models/export_mode.dart';
import 'package:jianjin/src/models/segment.dart';
import 'package:jianjin/src/services/ffmpeg_locator.dart';
import 'package:jianjin/src/services/ffmpeg_service.dart';
import 'package:jianjin/src/services/ffprobe_service.dart';

/// 端到端验证无损切割：造一个 GOP 已知的视频，走真实 ffmpeg 管线导出，
/// 再用 ffprobe 校验产物时长。这条链路错了，整个工具就没有价值。
void main() {
  late Directory tmp;
  late String fixture;
  var haveFfmpeg = false;

  setUpAll(() async {
    haveFfmpeg = await FfmpegLocator.probeVersion() != null;
    if (!haveFfmpeg) return;

    tmp = await Directory.systemTemp.createTemp('vs_itest_');
    fixture = p.join(tmp.path, 'fixture.mp4');

    // 30 秒，25fps，GOP=50 帧（即每 2 秒一个关键帧），带音轨
    final r = await Process.run(FfmpegLocator.ffmpeg, [
      '-v', 'error', '-y',
      '-f', 'lavfi', '-i', 'testsrc=duration=30:size=320x240:rate=25',
      '-f', 'lavfi', '-i', 'sine=frequency=440:duration=30',
      '-c:v', 'libx264', '-g', '50', '-keyint_min', '50',
      '-sc_threshold', '0', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-shortest',
      fixture,
    ]);
    expect(r.exitCode, 0, reason: '构造测试素材失败: ${r.stderr}');
  });

  tearDownAll(() async {
    if (haveFfmpeg && tmp.existsSync()) {
      await tmp.delete(recursive: true);
    }
  });

  test('ffprobe 读出正确的容器与流信息', () async {
    if (!haveFfmpeg) return;
    final info = await const FfprobeService().probe(fixture);

    expect(info.width, 320);
    expect(info.height, 240);
    expect(info.videoCodec, 'h264');
    expect(info.frameRate, closeTo(25, 0.1));
    expect(info.duration.inMilliseconds, closeTo(30000, 500));
  });

  test('关键帧按 2 秒间隔被正确提取', () async {
    if (!haveFfmpeg) return;
    final frames = await const FfprobeService().keyframes(fixture).last;

    expect(frames.length, greaterThan(10));
    expect(frames.first, Duration.zero);

    // GOP=50@25fps ⇒ 每 2 秒一个关键帧
    for (var i = 1; i < frames.length; i++) {
      final gap = frames[i] - frames[i - 1];
      expect(gap.inMilliseconds, closeTo(2000, 120),
          reason: '第 $i 个关键帧间隔异常: $gap');
    }
  });

  test('无损导出：起点吸附关键帧，终点精确（回归：终点曾被错误地向后吸附）',
      () async {
    if (!haveFfmpeg) return;

    var info = await const FfprobeService().probe(fixture);
    final frames = await const FfprobeService().keyframes(fixture).last;
    info = info.copyWith(keyframes: frames);

    // 故意选不在关键帧上的切点：5.4s → 15.4s（GOP 2s）
    const seg = Segment(
      id: 't1',
      start: Duration(milliseconds: 5400),
      end: Duration(milliseconds: 15400),
    );

    final range = ExportRange.of(info, seg.start, seg.end, ExportMode.lossless);

    // 起点必须向前吸附，否则无法从 GOP 中间无损 copy
    expect(range.start, const Duration(seconds: 4),
        reason: '起点应向前吸附到 4s');

    // 终点必须保持精确。向后吸附会白白多包一整个 GOP —— 这正是
    // 「标 5 秒导出 13 秒」的主因，不能回退。
    expect(range.end, const Duration(milliseconds: 15400),
        reason: '终点不应被吸附，必须精确');

    final out = p.join(tmp.path, 'out_lossless.mp4');
    await const FfmpegService()
        .exportSegment(info: info, segment: seg, outputPath: out)
        .drain<void>();

    expect(File(out).existsSync(), isTrue, reason: '导出文件不存在');

    final outInfo = await const FfprobeService().probe(out);
    expect(outInfo.duration.inMilliseconds, closeTo(11400, 400),
        reason: '产物应为 4s→15.4s 共 11.4s');

    // 无损：编码未变
    expect(outInfo.videoCodec, info.videoCodec);
  });

  test('精确模式导出的时长与标记区间一致', () async {
    if (!haveFfmpeg) return;

    var info = await const FfprobeService().probe(fixture);
    final frames = await const FfprobeService().keyframes(fixture).last;
    info = info.copyWith(keyframes: frames);

    const seg = Segment(
      id: 't2',
      start: Duration(milliseconds: 5400),
      end: Duration(milliseconds: 10400),
    );

    final range = ExportRange.of(info, seg.start, seg.end, ExportMode.precise);
    expect(range.start, seg.start);
    expect(range.end, seg.end);
    expect(range.hasDrift, isFalse);

    final out = p.join(tmp.path, 'out_precise.mp4');
    await const FfmpegService()
        .exportSegment(
          info: info,
          segment: seg,
          outputPath: out,
          mode: ExportMode.precise,
        )
        .drain<void>();

    final outInfo = await const FfprobeService().probe(out);
    expect(outInfo.duration.inMilliseconds, closeTo(5000, 300),
        reason: '精确模式应严格等于标记的 5s');
  });

  test('ExportRange 报出的偏差与实际产物一致', () async {
    if (!haveFfmpeg) return;

    var info = await const FfprobeService().probe(fixture);
    final frames = await const FfprobeService().keyframes(fixture).last;
    info = info.copyWith(keyframes: frames);

    const seg = Segment(
      id: 't3',
      start: Duration(milliseconds: 7300),
      end: Duration(milliseconds: 12300),
    );
    final range = ExportRange.of(info, seg.start, seg.end, ExportMode.lossless);

    // 起点 7.3s 吸附到 6s ⇒ 多出 1.3s
    expect(range.drift, const Duration(milliseconds: 1300));
    expect(range.hasDrift, isTrue);

    final out = p.join(tmp.path, 'out_drift.mp4');
    await const FfmpegService()
        .exportSegment(info: info, segment: seg, outputPath: out)
        .drain<void>();

    final outInfo = await const FfprobeService().probe(out);
    // 界面上报的 drift 必须和真实产物吻合，否则又是在撒谎
    expect(outInfo.duration.inMilliseconds,
        closeTo(range.duration.inMilliseconds, 400));
  });

  test('波形抽取返回归一化包络', () async {
    if (!haveFfmpeg) return;
    final w = await const FfmpegService().waveform(fixture, buckets: 200);

    expect(w.length, 200);
    expect(w.every((v) => v >= 0 && v <= 1), isTrue);
    // 素材是持续正弦波，应当整体有声而非静音
    expect(w.where((v) => v > 0.1).length, greaterThan(150));
  });
}
