import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianjin/src/services/ffmpeg_locator.dart';
import 'package:path/path.dart' as p;

/// 用户手选路径的行为。这里的每一条都对应一种「用户以为设了、其实没生效」
/// 或者反过来「设过一次就再也回不去」的故障。
void main() {
  late Directory tmp;
  late File fakeFfmpeg;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('jianjin_locator_');
    fakeFfmpeg = File(p.join(tmp.path, 'ffmpeg'))..writeAsStringSync('#!/bin/sh');
    FfmpegLocator.setOverrides(ffmpeg: null, ffprobe: null);
    FfmpegLocator.invalidate();
  });

  tearDown(() {
    FfmpegLocator.setOverrides(ffmpeg: null, ffprobe: null);
    FfmpegLocator.invalidate();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('指定的路径存在时优先于自动查找', () {
    FfmpegLocator.setOverrides(ffmpeg: fakeFfmpeg.path);
    expect(FfmpegLocator.ffmpeg, fakeFfmpeg.path);

    final s = FfmpegLocator.ffmpegStatus;
    expect(s.fromCustom, isTrue);
    expect(s.customValid, isTrue);
    expect(s.customStale, isFalse);
  });

  test('指定的路径失效时回退到自动查找，并把「失效」暴露出来', () {
    FfmpegLocator.setOverrides(ffmpeg: fakeFfmpeg.path);
    expect(FfmpegLocator.ffmpeg, fakeFfmpeg.path);

    // 用户升级 / 清理后二进制没了
    fakeFfmpeg.deleteSync();
    FfmpegLocator.invalidate();

    expect(FfmpegLocator.ffmpeg, isNot(fakeFfmpeg.path),
        reason: '一次失效的选择不该把应用永久钉死在找不到的状态');

    final s = FfmpegLocator.ffmpegStatus;
    expect(s.customStale, isTrue, reason: '回退必须可见，不能静默');
    expect(s.fromCustom, isFalse);
    expect(s.custom, fakeFfmpeg.path, reason: '仍要显示用户设过什么');
  });

  test('空串与纯空白等同于未指定', () {
    FfmpegLocator.setOverrides(ffmpeg: '   ');
    expect(FfmpegLocator.ffmpegStatus.custom, isNull);
    expect(FfmpegLocator.ffmpegStatus.fromCustom, isFalse);
  });

  test('改路径会让缓存失效——否则设置改了也要等重启才生效', () {
    final first = FfmpegLocator.ffmpeg;
    FfmpegLocator.setOverrides(ffmpeg: fakeFfmpeg.path);
    expect(FfmpegLocator.ffmpeg, isNot(first));
    expect(FfmpegLocator.ffmpeg, fakeFfmpeg.path);
  });

  test('清除后回到自动查找', () {
    FfmpegLocator.setOverrides(ffmpeg: fakeFfmpeg.path);
    expect(FfmpegLocator.ffmpeg, fakeFfmpeg.path);

    FfmpegLocator.setOverrides(ffmpeg: null);
    expect(FfmpegLocator.ffmpeg, isNot(fakeFfmpeg.path));
    expect(FfmpegLocator.ffmpegStatus.custom, isNull);
  });

  test('ffmpeg 与 ffprobe 各自独立', () {
    FfmpegLocator.setOverrides(ffmpeg: fakeFfmpeg.path);
    expect(FfmpegLocator.ffmpeg, fakeFfmpeg.path);
    expect(FfmpegLocator.ffprobeStatus.fromCustom, isFalse);
    expect(FfmpegLocator.ffprobe, isNot(fakeFfmpeg.path));
  });

  group('缺二进制的错误识别', () {
    test('认出 dart:io 找不到可执行文件时抛的 ProcessException', () {
      // 这就是 Process.run('ffprobe', ...) 在没装 ffmpeg 的机器上的原文
      const err = 'ProcessException: No such file or directory\n'
          '  Command: ffprobe -v error -print_format json a.mp4';
      expect(FfmpegLocator.looksLikeMissingBinary(err), isTrue);
    });

    test('ffmpeg 与 ffprobe 都认', () {
      expect(
        FfmpegLocator.looksLikeMissingBinary(
            'ProcessException: ...\n  Command: ffmpeg -i a.mp4'),
        isTrue,
      );
    });

    test('文件本身的问题不算——那种要照原样告诉用户', () {
      expect(
        FfmpegLocator.looksLikeMissingBinary('Exception: 文件中没有视频流'),
        isFalse,
      );
      expect(
        FfmpegLocator.looksLikeMissingBinary('Exception: ffprobe 失败: 坏文件'),
        isFalse,
        reason: 'ffprobe 跑起来了、只是文件有问题，不该把人引去设路径',
      );
      expect(FfmpegLocator.looksLikeMissingBinary(null), isFalse);
    });
  });

  test('跑不起来的文件 versionOf 返回 null 而不是抛异常', () async {
    expect(await FfmpegLocator.versionOf(fakeFfmpeg.path), isNull);
    expect(
      await FfmpegLocator.versionOf(p.join(tmp.path, '不存在的东西')),
      isNull,
    );
  });
}
