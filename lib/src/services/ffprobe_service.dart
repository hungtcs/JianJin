import 'dart:convert';
import 'dart:io';

import '../models/video_info.dart';
import 'ffmpeg_locator.dart';

class FfprobeService {
  const FfprobeService();

  /// 读取容器/流元数据。不解码，很快。
  Future<VideoInfo> probe(String path) async {
    final r = await Process.run(FfmpegLocator.ffprobe, [
      '-v', 'error',
      '-print_format', 'json',
      '-show_format',
      '-show_streams',
      path,
    ]);
    if (r.exitCode != 0) {
      throw Exception('ffprobe 失败: ${r.stderr}');
    }

    final json = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    final streams = (json['streams'] as List).cast<Map<String, dynamic>>();
    final format = json['format'] as Map<String, dynamic>;

    final video = streams.firstWhere(
      (s) => s['codec_type'] == 'video',
      orElse: () => throw Exception('文件中没有视频流'),
    );
    final audio = streams.cast<Map<String, dynamic>?>().firstWhere(
          (s) => s?['codec_type'] == 'audio',
          orElse: () => null,
        );

    final durSec = double.tryParse('${format['duration']}') ?? 0.0;

    return VideoInfo(
      path: path,
      duration: Duration(milliseconds: (durSec * 1000).round()),
      width: (video['width'] as num?)?.toInt() ?? 0,
      height: (video['height'] as num?)?.toInt() ?? 0,
      videoCodec: '${video['codec_name'] ?? 'unknown'}',
      audioCodec: '${audio?['codec_name'] ?? '无音轨'}',
      frameRate: _parseRate('${video['avg_frame_rate'] ?? '0/1'}'),
      container: '${format['format_name'] ?? ''}'.split(',').first,
    );
  }

  static double _parseRate(String s) {
    final parts = s.split('/');
    if (parts.length != 2) return double.tryParse(s) ?? 0;
    final n = double.tryParse(parts[0]) ?? 0;
    final d = double.tryParse(parts[1]) ?? 1;
    return d == 0 ? 0 : n / d;
  }

  /// 提取关键帧时间点。
  ///
  /// 用 packet 而非 frame：`-show_entries frame=...` 需要真正解码整个文件，
  /// 长视频要几分钟；读 packet 只解析容器索引，快一个数量级。
  /// 输出行形如 `12.345000,K__`，K 标志即关键帧。
  Stream<List<Duration>> keyframes(String path) async* {
    final proc = await Process.start(FfmpegLocator.ffprobe, [
      '-v', 'error',
      '-select_streams', 'v:0',
      '-show_entries', 'packet=pts_time,flags',
      '-of', 'csv=print_section=0',
      path,
    ]);

    final acc = <Duration>[];
    var lastEmit = 0;

    await for (final line in proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final parts = line.split(',');
      if (parts.length < 2) continue;
      if (!parts[1].startsWith('K')) continue;
      final t = double.tryParse(parts[0]);
      if (t == null) continue;
      acc.add(Duration(milliseconds: (t * 1000).round()));

      // 边扫边吐，时间轴上的关键帧刻度可以渐进出现，不用干等
      if (acc.length - lastEmit >= 200) {
        lastEmit = acc.length;
        yield List.unmodifiable(acc);
      }
    }

    await proc.exitCode;
    acc.sort();
    yield List.unmodifiable(acc);
  }

  /// 静音区间检测，用于自动提议片段（录屏/讲座场景收益最大）。
  /// 返回的是「静音」区间，取补集即为有声内容。
  Future<List<(Duration, Duration)>> detectSilence(
    String path, {
    double noiseDb = -30,
    double minDurationSec = 1.0,
  }) async {
    final proc = await Process.start(FfmpegLocator.ffmpeg, [
      '-v', 'info',
      '-i', path,
      '-af', 'silencedetect=noise=${noiseDb}dB:d=$minDurationSec',
      '-f', 'null',
      '-',
    ]);

    final out = <(Duration, Duration)>[];
    Duration? pendingStart;

    final startRe = RegExp(r'silence_start:\s*([0-9.]+)');
    final endRe = RegExp(r'silence_end:\s*([0-9.]+)');

    await for (final line in proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final ms = startRe.firstMatch(line);
      if (ms != null) {
        final v = double.tryParse(ms.group(1)!);
        if (v != null) pendingStart = Duration(milliseconds: (v * 1000).round());
        continue;
      }
      final me = endRe.firstMatch(line);
      if (me != null && pendingStart != null) {
        final v = double.tryParse(me.group(1)!);
        if (v != null) {
          out.add((pendingStart, Duration(milliseconds: (v * 1000).round())));
        }
        pendingStart = null;
      }
    }

    await proc.exitCode;
    return out;
  }
}
