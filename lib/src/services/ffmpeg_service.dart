import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/export_mode.dart';
import '../models/segment.dart';
import '../models/video_info.dart';
import 'ffmpeg_locator.dart';

/// 输出文件已存在时怎么办
enum OverwritePolicy {
  /// 覆盖同名文件
  overwrite,

  /// 跳过已存在的片段，只导出新的
  skip,

  /// 自动在文件名后加序号，两份都保留
  rename,
}

class ExportProgress {
  const ExportProgress({
    required this.segmentIndex,
    required this.segmentCount,
    required this.fraction,
    required this.outputPath,
    this.done = false,
    this.error,
    this.skipped = false,
  });

  final int segmentIndex;
  final int segmentCount;

  /// 当前片段的完成比例 0..1
  final double fraction;
  final String outputPath;
  final bool done;
  final String? error;

  /// 因目标已存在且策略为 skip 而未导出
  final bool skipped;

  /// 总体进度：已完成片段数 + 当前片段进度
  double get overall =>
      segmentCount == 0 ? 0 : (segmentIndex + fraction) / segmentCount;
}

class FfmpegService {
  const FfmpegService();

  /// 导出单个片段。
  ///
  /// 无损模式：`-ss` 置于 `-i` 之前，用容器索引快速定位到吸附后的起点关键帧，
  /// 全程 `-c copy` 零重编码。**终点不做吸附**——解码器读到 `-t` 指定的时长
  /// 就停止，向后吸附只会白白多包一整个 GOP。
  ///
  /// 精确模式：重编码，边界帧级准确，代价是慢且有损。
  Stream<double> exportSegment({
    required VideoInfo info,
    required Segment segment,
    required String outputPath,
    ExportMode mode = ExportMode.lossless,
  }) async* {
    final range = ExportRange.of(info, segment.start, segment.end, mode);
    final dur = range.duration;
    if (dur <= Duration.zero) {
      throw ArgumentError('片段时长为零：${segment.id}');
    }

    final args = <String>[
      '-hide_banner',
      '-nostdin',
      '-ss', _ffTime(range.start),
      '-i', info.path,
      '-t', _ffTime(dur),
      '-map', '0:v:0',
      '-map', '0:a?',
      if (mode == ExportMode.lossless) ...[
        '-c', 'copy',
      ] else ...[
        '-c:v', 'libx264',
        '-crf', '18',
        '-preset', 'veryfast',
        '-pix_fmt', 'yuv420p',
        '-c:a', 'aac',
        '-b:a', '192k',
      ],
      '-avoid_negative_ts', 'make_zero',
      '-progress', 'pipe:1',
      '-y',
      outputPath,
    ];

    final proc = await Process.start(FfmpegLocator.ffmpeg, args);

    // stderr 要持续排空，否则管道写满会让 ffmpeg 阻塞
    final errBuf = StringBuffer();
    unawaited(proc.stderr
        .transform(utf8.decoder)
        .forEach((c) => errBuf.write(c)));

    final totalUs = dur.inMicroseconds;
    await for (final line in proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.startsWith('out_time_us=')) {
        final v = int.tryParse(line.substring('out_time_us='.length).trim());
        if (v != null && totalUs > 0) {
          yield (v / totalUs).clamp(0.0, 1.0);
        }
      } else if (line.startsWith('progress=end')) {
        yield 1.0;
      }
    }

    final code = await proc.exitCode;
    if (code != 0) {
      throw Exception('导出失败 (exit $code)\n${errBuf.toString().trim()}');
    }
  }

  /// 片段 [index]（从 0 起）的默认输出文件名。
  /// 界面要在导出前检测冲突，必须和实际写入用同一套命名规则。
  static String outputNameFor(VideoInfo info, int index) {
    final ext = p.extension(info.path);
    final stem = p.basenameWithoutExtension(info.path);
    return '${stem}_${(index + 1).toString().padLeft(3, '0')}$ext';
  }

  /// 本次导出将要写入的全部路径（未考虑改名策略）。
  static List<String> plannedOutputs({
    required VideoInfo info,
    required int segmentCount,
    required String outputDir,
  }) {
    return [
      for (var i = 0; i < segmentCount; i++)
        p.join(outputDir, outputNameFor(info, i)),
    ];
  }

  /// 在 [path] 基础上找一个尚未占用的名字：`name-2.mp4`、`name-3.mp4`……
  static String freePathFor(String path) {
    if (!File(path).existsSync()) return path;
    final dir = p.dirname(path);
    final ext = p.extension(path);
    final stem = p.basenameWithoutExtension(path);
    for (var n = 2; n < 1000; n++) {
      final candidate = p.join(dir, '$stem-$n$ext');
      if (!File(candidate).existsSync()) return candidate;
    }
    return path;
  }

  /// 批量导出，串行执行（并行会抢 IO 反而更慢）。
  Stream<ExportProgress> exportAll({
    required VideoInfo info,
    required List<Segment> segments,
    required String outputDir,
    ExportMode mode = ExportMode.lossless,
    OverwritePolicy policy = OverwritePolicy.overwrite,
  }) async* {
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      var out = p.join(outputDir, outputNameFor(info, i));

      if (File(out).existsSync()) {
        switch (policy) {
          case OverwritePolicy.skip:
            yield ExportProgress(
              segmentIndex: i,
              segmentCount: segments.length,
              fraction: 1,
              outputPath: out,
              skipped: true,
            );
            continue;
          case OverwritePolicy.rename:
            out = freePathFor(out);
          case OverwritePolicy.overwrite:
            break;
        }
      }

      try {
        await for (final f in exportSegment(
          info: info,
          segment: seg,
          outputPath: out,
          mode: mode,
        )) {
          yield ExportProgress(
            segmentIndex: i,
            segmentCount: segments.length,
            fraction: f,
            outputPath: out,
          );
        }
        yield ExportProgress(
          segmentIndex: i,
          segmentCount: segments.length,
          fraction: 1,
          outputPath: out,
        );
      } catch (e) {
        yield ExportProgress(
          segmentIndex: i,
          segmentCount: segments.length,
          fraction: 0,
          outputPath: out,
          error: '$e',
        );
      }
    }

    yield ExportProgress(
      segmentIndex: segments.length,
      segmentCount: segments.length,
      fraction: 1,
      outputPath: outputDir,
      done: true,
    );
  }

  /// 抽取音频包络用于画波形。
  ///
  /// 重采样到 1kHz 单声道再取桶内峰值：1 小时素材约 7MB，
  /// 足够画出静音/有声的对比，又不至于把内存吃爆。
  /// 无音轨时返回空列表而不是抛错。
  Future<List<double>> waveform(
    String path, {
    int buckets = 4000,
  }) async {
    const rate = 1000;
    late Process proc;
    try {
      proc = await Process.start(FfmpegLocator.ffmpeg, [
        '-v', 'error',
        '-nostdin',
        '-i', path,
        '-map', '0:a:0',
        '-ac', '1',
        '-ar', '$rate',
        '-f', 's16le',
        '-',
      ]);
    } catch (_) {
      return const <double>[];
    }

    final bytes = BytesBuilder(copy: false);
    unawaited(proc.stderr.drain<void>());
    await for (final chunk in proc.stdout) {
      bytes.add(chunk);
    }
    final code = await proc.exitCode;
    if (code != 0) return const <double>[];

    final data = bytes.takeBytes();
    final samples = Int16List.view(
      data.buffer,
      data.offsetInBytes,
      data.lengthInBytes ~/ 2,
    );
    if (samples.isEmpty) return const <double>[];

    final n = buckets.clamp(1, samples.length);
    final out = List<double>.filled(n, 0);
    final per = samples.length / n;

    for (var i = 0; i < n; i++) {
      final lo = (i * per).floor();
      final hi = ((i + 1) * per).ceil().clamp(0, samples.length);
      var peak = 0;
      for (var j = lo; j < hi; j++) {
        final v = samples[j].abs();
        if (v > peak) peak = v;
      }
      out[i] = peak / 32768.0;
    }

    // 按素材自身峰值归一化。绝对电平（相对满刻度 32768）对显示没有意义：
    // 多数素材的峰值远低于满刻度，直接画出来只占轨道很小一部分，
    // 把轨道拉高也看不出细节。
    //
    // 但接近静音的音轨不做放大，否则底噪会被拉成满幅波形，
    // 让人误以为那里有内容——而「一眼看出静音段」正是波形的主要用途。
    var loudest = 0.0;
    for (final v in out) {
      if (v > loudest) loudest = v;
    }
    if (loudest > 0.02) {
      for (var i = 0; i < out.length; i++) {
        out[i] = out[i] / loudest;
      }
    }
    return out;
  }

  /// 生成缩略图条。
  ///
  /// **只解关键帧**（`-skip_frame nokey`）。此前用 `-vf fps=N` 取图，那会让
  /// ffmpeg 解码整部影片的每一帧再丢掉绝大多数——4K 素材上尤其昂贵，实测同
  /// 素材比只解关键帧慢 6 倍以上，而且会和播放抢 CPU 造成卡顿。
  ///
  /// 顺带一个好处：取出的正是关键帧，而关键帧就是无损切割唯一能下刀的位置，
  /// 缩略图与可切点从此天然对齐。
  ///
  /// [keyframeCount] 用于把产出裁到 [count] 附近；传 0 表示未知，此时不抽稀。
  Future<List<String>> thumbnails({
    required VideoInfo info,
    required String cacheDir,
    int keyframeCount = 0,
    int count = 240,
    int width = 160,
  }) async {
    final dir = Directory(cacheDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    if (info.duration <= Duration.zero) return const <String>[];

    // 关键帧太密时按固定步长抽稀，避免一部长片写出上万个文件
    final stride = keyframeCount > count ? (keyframeCount / count).ceil() : 1;
    final filters = <String>[
      if (stride > 1) "select='not(mod(n\\,$stride))'",
      'scale=$width:-2',
    ].join(',');

    final r = await Process.run(FfmpegLocator.ffmpeg, [
      '-v', 'error',
      '-nostdin',
      // 必须在 -i 之前：它是解码器选项，放后面对输入不生效
      '-skip_frame', 'nokey',
      '-i', info.path,
      '-vf', filters,
      // 按解码顺序原样输出，不要为了凑帧率复制或丢弃
      '-fps_mode', 'passthrough',
      '-f', 'image2',
      '-y',
      p.join(cacheDir, 'thumb_%06d.jpg'),
    ]);
    if (r.exitCode != 0) return const <String>[];

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('thumb_'))
        .map((f) => f.path)
        .toList()
      ..sort();
    return files;
  }

  /// ffmpeg 接受的时间格式，用秒 + 毫秒最稳妥
  static String _ffTime(Duration d) {
    final totalMs = d.inMilliseconds;
    final s = totalMs ~/ 1000;
    final ms = totalMs % 1000;
    return '$s.${ms.toString().padLeft(3, '0')}';
  }
}
