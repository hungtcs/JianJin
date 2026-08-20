import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'models/export_mode.dart';

/// 用户设置。改动即写盘，不需要「保存」按钮——设置项都是即时生效的开关。
///
/// 缩略图与波形默认开启，但它们是打开文件后最昂贵的两项分析：
/// 缩略图要解码全部关键帧，波形要解码整条音轨。素材很大或机器较弱时
/// 关掉它们能立刻消除卡顿，这也是把它们放进设置的主要原因。
class AppSettings extends ChangeNotifier {
  AppSettings._(this._file, this._values);

  final File? _file;
  Map<String, dynamic> _values;

  static const _kThumbnails = 'thumbnails';
  static const _kWaveform = 'waveform';
  static const _kExportMode = 'exportMode';
  static const _kThumbnailCount = 'thumbnailCount';
  static const _kTimelineHeight = 'timelineHeight';

  bool get thumbnailsEnabled => _values[_kThumbnails] as bool? ?? true;
  bool get waveformEnabled => _values[_kWaveform] as bool? ?? true;

  /// 目标缩略图数量。实际张数受关键帧数量限制，只多不少地向这个值靠拢。
  int get thumbnailCount => _values[_kThumbnailCount] as int? ?? 240;

  /// 细节轨总高度，由播放区与底部之间的分隔条拖拽设定
  double get timelineHeight =>
      (_values[_kTimelineHeight] as num?)?.toDouble() ?? 96.0;

  ExportMode get exportMode => ExportMode.values.firstWhere(
        (m) => m.name == _values[_kExportMode],
        orElse: () => ExportMode.lossless,
      );

  // 比较一律针对**生效值**而非存储值：默认项尚未写进配置文件时存的是 null，
  // 若拿原始值比较，「设成和默认值一样」也会触发通知与写盘。
  set thumbnailsEnabled(bool v) {
    if (thumbnailsEnabled == v) return;
    _set(_kThumbnails, v);
  }

  set waveformEnabled(bool v) {
    if (waveformEnabled == v) return;
    _set(_kWaveform, v);
  }

  set thumbnailCount(int v) {
    final clamped = v.clamp(40, 2000);
    if (thumbnailCount == clamped) return;
    _set(_kThumbnailCount, clamped);
  }

  set exportMode(ExportMode v) {
    if (exportMode == v) return;
    _set(_kExportMode, v.name);
  }

  set timelineHeight(double v) {
    final clamped = v.clamp(48.0, 420.0);
    if (timelineHeight == clamped) return;
    _set(_kTimelineHeight, clamped);
  }

  void _set(String key, Object? value) {
    _values = {..._values, key: value};
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    final f = _file;
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(_values));
    } catch (_) {
      // 写不进配置目录不该影响使用，设置退化为「本次运行有效」
    }
  }

  /// 各平台的标准配置位置。不引 path_provider——这点路径逻辑用
  /// 环境变量就能覆盖，为它加一个插件依赖不划算。
  static File? _configFile() {
    final env = Platform.environment;
    String? dir;
    if (Platform.isLinux) {
      dir = env['XDG_CONFIG_HOME'];
      if (dir == null || dir.isEmpty) {
        final home = env['HOME'];
        dir = home == null ? null : p.join(home, '.config');
      }
      dir = dir == null ? null : p.join(dir, 'jianjin');
    } else if (Platform.isMacOS) {
      final home = env['HOME'];
      dir = home == null
          ? null
          : p.join(home, 'Library', 'Application Support', 'JianJin');
    } else if (Platform.isWindows) {
      final appData = env['APPDATA'];
      dir = appData == null ? null : p.join(appData, 'JianJin');
    }
    return dir == null ? null : File(p.join(dir, 'settings.json'));
  }

  static Future<AppSettings> load() async {
    final file = _configFile();
    Map<String, dynamic> values = {};
    try {
      if (file != null && await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) values = decoded;
      }
    } catch (_) {
      // 配置文件损坏时退回默认值，不要让应用打不开
    }
    return AppSettings._(file, values);
  }

  /// 测试用：不落盘
  @visibleForTesting
  static AppSettings memory([Map<String, dynamic>? initial]) =>
      AppSettings._(null, initial ?? {});
}
