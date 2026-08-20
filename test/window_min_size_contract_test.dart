import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 最小窗口尺寸横跨三个平台的原生 runner，用三种语言各写一遍。
/// 三份数值没有任何机制保证一致——改了一处忘了另外两处，编译全过、测试全绿，
/// 只有在那个平台上手动拖窗口才会发现。这里把它们对齐。
///
/// 各平台的实现手段不同（macOS 是 contentMinSize，Linux 是 GDK 几何提示，
/// Windows 是 WM_GETMINMAXINFO），能核对的只有数值本身，那也正是会漂的部分。
String _read(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    fail('找不到 $path；本测试需要从仓库根目录运行');
  }
  return f.readAsStringSync();
}

({int width, int height}) _minSize(String source, String path) {
  final w = RegExp(r'kMinWindowWidth\s*=\s*(\d+)').firstMatch(source);
  final h = RegExp(r'kMinWindowHeight\s*=\s*(\d+)').firstMatch(source);
  expect(w, isNotNull, reason: '$path 里没有 kMinWindowWidth');
  expect(h, isNotNull, reason: '$path 里没有 kMinWindowHeight');
  return (width: int.parse(w!.group(1)!), height: int.parse(h!.group(1)!));
}

void main() {
  const runners = <String, String>{
    'macOS': 'macos/Runner/MainFlutterWindow.swift',
    'Linux': 'linux/runner/my_application.cc',
    'Windows': 'windows/runner/win32_window.cpp',
  };

  test('三端的最小窗口尺寸一致', () {
    final sizes = <String, ({int width, int height})>{
      for (final e in runners.entries) e.key: _minSize(_read(e.value), e.value),
    };

    final distinct = sizes.values.map((s) => '${s.width}x${s.height}').toSet();
    expect(
      distinct.length,
      1,
      reason: '三端不一致：${sizes.map((k, v) => MapEntry(k, '${v.width}x${v.height}'))}',
    );
  });

  test('最小尺寸容得下固定不可压缩的那几条', () {
    final size = _minSize(_read(runners['macOS']!), runners['macOS']!);

    // 侧栏是固定宽度，视频区再窄也得剩下点东西
    expect(size.width, greaterThan(232 + 300),
        reason: '侧栏 232 固定宽，剩下的才是视频区');
    // 标题栏 34 + 传输栏 44 + 全片条 34 + 时间轴默认 96 = 208
    expect(size.height, greaterThan(208 + 200),
        reason: '除去固定的 208 高，视频区至少还要 200');
  });

  test('每个 runner 都真的用上了这两个常量，而不只是定义了', () {
    // macOS：contentMinSize
    expect(
      _read(runners['macOS']!),
      contains('contentMinSize'),
      reason: '光定义常量不设到窗口上，限制不会生效',
    );
    // Linux：几何提示
    expect(_read(runners['Linux']!), contains('GDK_HINT_MIN_SIZE'));
    // Windows：模板默认没有这个分支，缺了就完全没有下限
    expect(_read(runners['Windows']!), contains('WM_GETMINMAXINFO'));
  });
}
