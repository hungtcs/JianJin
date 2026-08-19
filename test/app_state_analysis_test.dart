import 'package:flutter_test/flutter_test.dart';
import 'package:jianjin/src/models/video_info.dart';
import 'package:jianjin/src/services/ffmpeg_service.dart';
import 'package:jianjin/src/services/ffprobe_service.dart';
import 'package:jianjin/src/settings.dart';
import 'package:jianjin/src/state/app_state.dart';

/// 分析任务只在打开文件时跑一次。若那时对应开关是关的，就完全没有数据；
/// 之后在设置里打开只会显示一条空带——必须按需补算。
class FakeProbe implements FfprobeService {
  @override
  Future<VideoInfo> probe(String path) async => VideoInfo(
        path: path,
        duration: const Duration(minutes: 1),
        width: 1920,
        height: 1080,
        videoCodec: 'h264',
        audioCodec: 'aac',
        frameRate: 30,
        container: 'mp4',
      );

  @override
  Stream<List<Duration>> keyframes(String path) async* {
    yield const [Duration.zero];
  }

  @override
  Future<List<(Duration, Duration)>> detectSilence(
    String path, {
    double noiseDb = -30,
    double minDurationSec = 1.0,
  }) async =>
      const [];
}

class FakeFfmpeg implements FfmpegService {
  int waveformCalls = 0;
  int thumbnailCalls = 0;

  @override
  Future<List<double>> waveform(String path, {int buckets = 4000}) async {
    waveformCalls++;
    return List<double>.filled(10, 0.5);
  }

  @override
  Future<List<String>> thumbnails({
    required VideoInfo info,
    required String cacheDir,
    int keyframeCount = 0,
    int count = 240,
    int width = 160,
  }) async {
    thumbnailCalls++;
    return const ['/tmp/a.jpg'];
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('打开时开关为关则不做分析，之后在设置里打开会补算', () async {
    final settings = AppSettings.memory({'waveform': false});
    final ffmpeg = FakeFfmpeg();
    final state = AppState(
      settings: settings,
      probe: FakeProbe(),
      ffmpeg: ffmpeg,
    );

    await state.open('/tmp/x.mp4');
    await Future<void>.delayed(Duration.zero);
    expect(ffmpeg.waveformCalls, 0, reason: '开关为关时不应起 ffmpeg 进程');

    settings.waveformEnabled = true;
    await Future<void>.delayed(Duration.zero);
    expect(ffmpeg.waveformCalls, 1, reason: '打开后应补算，否则只是一条空带');

    state.dispose();
  });

  test('已有数据时反复开关不会重复分析', () async {
    final settings = AppSettings.memory();
    final ffmpeg = FakeFfmpeg();
    final state = AppState(
      settings: settings,
      probe: FakeProbe(),
      ffmpeg: ffmpeg,
    );

    await state.open('/tmp/x.mp4');
    await Future<void>.delayed(Duration.zero);
    final after = ffmpeg.waveformCalls;

    settings.waveformEnabled = false;
    settings.waveformEnabled = true;
    await Future<void>.delayed(Duration.zero);

    expect(ffmpeg.waveformCalls, after, reason: '数据仍然有效，不该重跑');
    state.dispose();
  });
}
