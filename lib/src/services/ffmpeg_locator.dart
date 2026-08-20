import 'dart:io';

import 'package:path/path.dart' as p;

/// 一个外部二进制的解析结果。设置界面按它如实展示——用户手选的路径失效时
/// 必须看得见，而不是「怎么突然又不工作了」。
class BinaryStatus {
  const BinaryStatus({
    required this.custom,
    required this.customValid,
    required this.resolved,
    required this.fromCustom,
  });

  /// 用户在设置里指定的路径，null 表示没指定
  final String? custom;

  /// 指定的路径此刻是否真的存在
  final bool customValid;

  /// 实际会被调用的路径
  final String resolved;

  /// resolved 是否来自用户指定（false 即自动查找的结果）
  final bool fromCustom;

  /// 指定过、但已经失效——界面要提示「已回退到自动查找」
  bool get customStale => custom != null && !customValid;
}

/// 定位 ffmpeg / ffprobe。
///
/// 顺序：用户指定 → 应用同级目录 → macOS `.app` 内 Resources → 常见安装路径
/// → 系统 PATH。GUI 应用继承的 PATH 往往很贫瘠（尤其 macOS 从 Finder 启动时），
/// 所以不能只靠 PATH。
class FfmpegLocator {
  FfmpegLocator._();

  static String? _ffmpegOverride;
  static String? _ffprobeOverride;

  static String? _ffmpeg;
  static String? _ffprobe;

  static String get ffmpeg => _ffmpeg ??= _locate('ffmpeg', _ffmpegOverride);
  static String get ffprobe =>
      _ffprobe ??= _locate('ffprobe', _ffprobeOverride);

  /// 应用用户在设置里指定的路径。空串等同未指定。
  /// 幂等：路径没变就不动缓存，免得设置面板每次通知都让查找重跑一遍。
  static void setOverrides({String? ffmpeg, String? ffprobe}) {
    final a = _clean(ffmpeg);
    final b = _clean(ffprobe);
    if (a == _ffmpegOverride && b == _ffprobeOverride) return;
    _ffmpegOverride = a;
    _ffprobeOverride = b;
    _ffmpeg = null;
    _ffprobe = null;
  }

  /// 清空缓存，强制下次重新查找。用户装完 ffmpeg 点「重新检测」时需要——
  /// 否则启动时缓存下来的「没找到」会一直跟到进程结束。
  static void invalidate() {
    _ffmpeg = null;
    _ffprobe = null;
  }

  static BinaryStatus get ffmpegStatus => _status(_ffmpegOverride, ffmpeg);
  static BinaryStatus get ffprobeStatus => _status(_ffprobeOverride, ffprobe);

  static BinaryStatus _status(String? override, String resolved) {
    final valid = override != null && _isFile(override);
    return BinaryStatus(
      custom: override,
      customValid: valid,
      resolved: resolved,
      fromCustom: valid && resolved == override,
    );
  }

  static String? _clean(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  static String _exeName(String base) =>
      Platform.isWindows ? '$base.exe' : base;

  static bool _isFile(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static String _locate(String base, String? override) {
    final exe = _exeName(base);

    // 0) 用户指定。**存在才采纳**：手选的文件被删掉或升级后改了路径时
    //    自动回落，否则一次失效的选择会把应用永久钉死在找不到的状态。
    //    回落的事实由 BinaryStatus.customStale 暴露给设置界面，不静默。
    if (override != null && _isFile(override)) return override;

    // 1) 应用同级目录（打包分发时把二进制放这里）
    final bundled = p.join(
      p.dirname(Platform.resolvedExecutable),
      exe,
    );
    if (_isFile(bundled)) return bundled;

    // 2) macOS .app 内部 Resources
    if (Platform.isMacOS) {
      final res = p.normalize(p.join(
        p.dirname(Platform.resolvedExecutable),
        '..',
        'Resources',
        exe,
      ));
      if (_isFile(res)) return res;
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
      if (_isFile(f)) return f;
    }

    // 4) 交给系统 PATH 解析
    return exe;
  }

  /// 返回版本首行，找不到或跑不起来返回 null。
  /// 用于启动自检，以及在用户手选路径时先验证再保存。
  static Future<String?> versionOf(String exe) async {
    try {
      final r = await Process.run(exe, ['-version']);
      if (r.exitCode != 0) return null;
      final out = (r.stdout as String).split('\n');
      if (out.isEmpty) return null;
      final first = out.first.trim();
      return first.isEmpty ? null : first;
    } catch (_) {
      return null;
    }
  }

  /// 一条错误信息是不是「二进制根本没跑起来」。
  ///
  /// dart:io 在找不到可执行文件时抛 ProcessException，其 toString 里带着
  /// 完整命令行。界面据此把用户引到设置里去指定路径，而不是甩一句
  /// 「ProcessException: No such file or directory」。
  static bool looksLikeMissingBinary(String? error) {
    if (error == null) return false;
    if (!error.contains('ProcessException')) return false;
    return error.contains('ffmpeg') || error.contains('ffprobe');
  }

  static Future<String?> probeVersion() => versionOf(ffmpeg);
  static Future<String?> probeProbeVersion() => versionOf(ffprobe);
}
