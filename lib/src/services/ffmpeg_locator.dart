import 'dart:io';

import 'package:path/path.dart' as p;

/// 定位 ffmpeg / ffprobe。
/// 优先用随应用分发的副本（保证版本一致），否则回落到 PATH。
class FfmpegLocator {
  FfmpegLocator._();

  static String? _ffmpeg;
  static String? _ffprobe;

  static String get ffmpeg => _ffmpeg ??= _locate('ffmpeg');
  static String get ffprobe => _ffprobe ??= _locate('ffprobe');

  static bool get isAvailable {
    try {
      return File(ffmpeg).existsSync() || ffmpeg == _exeName('ffmpeg');
    } catch (_) {
      return false;
    }
  }

  static String _exeName(String base) =>
      Platform.isWindows ? '$base.exe' : base;

  static String _locate(String base) {
    final exe = _exeName(base);

    // 1) 应用同级目录（打包分发时把二进制放这里）
    final bundled = p.join(
      p.dirname(Platform.resolvedExecutable),
      exe,
    );
    if (File(bundled).existsSync()) return bundled;

    // 2) macOS .app 内部 Resources
    if (Platform.isMacOS) {
      final res = p.normalize(p.join(
        p.dirname(Platform.resolvedExecutable),
        '..',
        'Resources',
        exe,
      ));
      if (File(res).existsSync()) return res;
    }

    // 3) 常见安装路径（GUI 应用继承的 PATH 往往很贫瘠，尤其 macOS）
    const candidates = <String>[
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/usr/bin',
      '/snap/bin',
      r'C:\Program Files\ffmpeg\bin',
    ];
    for (final dir in candidates) {
      final f = p.join(dir, exe);
      if (File(f).existsSync()) return f;
    }

    // 4) 交给系统 PATH 解析
    return exe;
  }

  /// 返回版本首行，找不到返回 null。用于启动时自检并给出可操作的提示。
  static Future<String?> probeVersion() async {
    try {
      final r = await Process.run(ffmpeg, ['-version']);
      if (r.exitCode != 0) return null;
      final out = (r.stdout as String).split('\n');
      return out.isEmpty ? null : out.first.trim();
    } catch (_) {
      return null;
    }
  }
}
