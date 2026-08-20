import 'package:flutter/widgets.dart';

/// 全部 UI 自绘，不引入 material.dart。
/// 这里集中所有设计 token，任何颜色/尺寸都不应散落在 widget 里。
class AppColors {
  const AppColors._();

  static const bg = Color(0xFF161618);
  static const panel = Color(0xFF1F1F22);
  static const panelAlt = Color(0xFF27272B);
  static const border = Color(0xFF34343A);
  static const borderStrong = Color(0xFF45454D);

  static const text = Color(0xFFD8D8DB);
  static const textDim = Color(0xFF8B8B93);
  static const textFaint = Color(0xFF5E5E66);

  static const accent = Color(0xFF4A9EFF);
  static const accentDim = Color(0x334A9EFF);

  /// 已确认片段
  static const segment = Color(0xFF4ADE80);
  static const segmentFill = Color(0x2E4ADE80);
  static const segmentSelected = Color(0xFF86EFAC);

  /// 正在标记中（按了 I 还没按 O）
  static const pending = Color(0xFFFBBF24);
  static const pendingFill = Color(0x2EFBBF24);

  static const playhead = Color(0xFFFF5A5A);
  static const keyframe = Color(0xFF4E4E57);
  static const waveform = Color(0xFF596273);
  static const waveformLoud = Color(0xFF6B7689);
  static const danger = Color(0xFFFF5A5A);
}

class AppMetrics {
  const AppMetrics._();

  static const titleBarHeight = 34.0;
  static const transportHeight = 44.0;
  static const overviewHeight = 34.0;
  static const sidebarWidth = 232.0;

  static const radius = 5.0;
  static const gap = 8.0;
  static const padding = 12.0;

  /// 显式打点（I/O）不加留白：用户标的是哪就是哪，可预测优先。
  static const markPaddingMs = 0;

}

/// 跨平台系统字体栈，避免 Flutter 默认 Roboto 的「安卓味」
const kFontFallback = <String>[
  '.SF Pro Text',
  'SF Pro Text',
  'Segoe UI Variable Text',
  'Segoe UI',
  'Inter',
  'Cantarell',
  'Ubuntu',
  'Noto Sans CJK SC',
  'PingFang SC',
  'Microsoft YaHei',
];

const kMonoFallback = <String>[
  'SF Mono',
  'Menlo',
  'Cascadia Mono',
  'Consolas',
  'DejaVu Sans Mono',
  'monospace',
];

class AppText {
  const AppText._();

  static const base = TextStyle(
    color: AppColors.text,
    fontSize: 13,
    height: 1.35,
    fontFamilyFallback: kFontFallback,
    decoration: TextDecoration.none,
  );

  static const dim = TextStyle(
    color: AppColors.textDim,
    fontSize: 12,
    height: 1.35,
    fontFamilyFallback: kFontFallback,
    decoration: TextDecoration.none,
  );

  static const label = TextStyle(
    color: AppColors.textDim,
    fontSize: 11,
    height: 1.2,
    letterSpacing: 0.3,
    fontFamilyFallback: kFontFallback,
    decoration: TextDecoration.none,
  );

  /// 时间码等宽，避免数字跳动时抖动
  static const mono = TextStyle(
    color: AppColors.text,
    fontSize: 13,
    height: 1.2,
    fontFamilyFallback: kMonoFallback,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    decoration: TextDecoration.none,
  );

  static const monoDim = TextStyle(
    color: AppColors.textDim,
    fontSize: 12,
    height: 1.2,
    fontFamilyFallback: kMonoFallback,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    decoration: TextDecoration.none,
  );
}

/// 时间码格式化：时长 < 1h 时省略小时位，减少视觉噪音
String formatTime(Duration d, {bool withMillis = false}) {
  final neg = d.isNegative;
  final abs = d.abs();
  final h = abs.inHours;
  final m = abs.inMinutes % 60;
  final s = abs.inSeconds % 60;
  final ms = abs.inMilliseconds % 1000;

  final sb = StringBuffer(neg ? '-' : '');
  if (h > 0) {
    sb.write('$h:');
    sb.write(m.toString().padLeft(2, '0'));
  } else {
    sb.write(m.toString().padLeft(2, '0'));
  }
  sb.write(':');
  sb.write(s.toString().padLeft(2, '0'));
  if (withMillis) {
    sb.write('.');
    sb.write((ms ~/ 10).toString().padLeft(2, '0'));
  }
  return sb.toString();
}
